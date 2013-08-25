express = require "express"
http = require "http"
socket_io = require "socket.io"
request = require "request"
mongoose = require "mongoose"

mongoose.connect process.env.MONGODBSTR
mongoose.connection.once "error", ->
	console.error arguments
	process.exit 1

Task = mongoose.model "Task",
	userId: String
	path: String
	thumbnail: String
	type: String
	caption: String
	status: String
	downloadProgress: Number
	uploadProgress: Number

currentTasks = {}

expressServer = express()
expressServer.configure ->

	expressServer.use express.compress()
	expressServer.use express.bodyParser()
	expressServer.use (req, res, next) ->
		req.url =
			switch req.url
				when "/" then "/page.html"
				else req.url
		next()
	expressServer.use express.static "#{__dirname}/public", maxAge: 0, (err) -> console.log "Static: #{err}"
	expressServer.use expressServer.router

server = http.createServer expressServer

io = socket_io.listen server
io.configure ->

	io.set "log level", 0
	io.set "transports", ["xhr-polling"]
	io.set "polling duration", 10

io.sockets.on "connection", (socket) ->

	socket.on "handshake", ({userId}, callback) ->
		socket.userId = userId
		Task.find userId: socket.userId, (err, tasks) ->
			callback tasks: tasks

	socket.on "addTask", ({task}, callback) ->
		return callback success: false unless socket.userId?
		Task.update userId: socket.userId, path: task.path, {$setOnInsert: task}, (err, count, response) ->
			return callback success: false if response.updatedExisting
			callback success: true
			io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "addTask", task: task

	socket.on "removeTask", ({taskPath}, callback) ->
		return callback success: false unless socket.userId?
		Task.remove userId: socket.userId, path: taskPath, status: $nin: ["posting", "transferring"], (err, count) ->
			return callback success: false unless count is 1
			callback success: true
			io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "removeTask", taskPath: taskPath

	socket.on "captionChanged", ({taskPath, caption}) ->
		return unless socket.userId?
		Task.update userId: socket.userId, path: taskPath, status: $nin: ["posting", "post_success", "post_failure", "transferring"], {caption: caption}, (err, count) ->
			return unless count is 1
			io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "captionChanged", taskPath: taskPath, caption: caption

	socket.on "uploadTask", ({taskPath, fbAccessToken, albumId, delay}, callback) ->
		return callback success: false unless socket.userId?
		Task.findOneAndUpdate userId: socket.userId, path: taskPath, status: $nin: ["posting", "post_success", "post_failure", "transferring"], {status: "posting"}, (err, task) ->
			return callback success: false unless task?
			io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "posting", taskPath: taskPath
			if task.type is "photo"
				setTimeout(
					->
						request.post "https://graph.facebook.com/#{albumId ? socket.userId}/photos", form: access_token: fbAccessToken, url: taskPath, name: task.caption, (error, response, body) ->
							body = try JSON.parse body catch then body
							Task.update userId: socket.userId, path: taskPath, {status: unless error? or body.error? then "post_success" else "post_failure"}, (err, count) ->
								callback success: not (error? or body.error?)
								io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "uploadedTask", taskPath: taskPath, success: not (error? or body.error?)
					delay ? 0
				)
			else if task.type is "video"
				r2 = request.post "https://graph-video.facebook.com/me/videos", (error, response, body) ->
					body = try JSON.parse body catch then body
					Task.update userId: socket.userId, path: taskPath, {status: unless error? or body.error? then "post_success" else "post_failure"}, (err, count) ->
						callback success: not (error? or body.error?)
						io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "uploadedTask", taskPath: taskPath, success: not (error? or body.error?)
				form = r2.form()
				form.append "access_token", fbAccessToken
				form.append "title", task.caption ? ""
				form.append "file", r1 = request.get taskPath
				si = undefined
				r1.on "response", (response) ->
					Task.update userId: socket.userId, path: taskPath, {status: "transferring"}, (err, count) ->
						io.sockets.clients().filter((x) -> x.userId is socket.userId).forEach (x) -> x.emit "transferring", taskPath: taskPath
						fileSize = Number response.headers["content-length"]
						oldProgress = download: 0, upload: 0
						si = setInterval(
							->
								downloadProgress = (dp = r1.response?.connection?.socket.bytesRead ? 0) / fileSize * 100
								uploadProgress = (up = r2.req?.connection?.socket?._bytesDispatched ? 0) / fileSize * 100
								return if oldProgress.download is downloadProgress and oldProgress.upload is uploadProgress
								oldProgress = download: downloadProgress, upload: uploadProgress
								Task.update userId: socket.userId, path: taskPath, {downloadProgress: downloadProgress, uploadProgress: uploadProgress}, (err, count) ->
								io.sockets.clients().filter((x) -> x.userId is socket.userId).forEach (x) -> x.volatile.emit "progress", taskPath: taskPath, download: downloadProgress, upload: uploadProgress
								if dp - up > 5 * 1 << 20
									r1.pause()
									form.resume()
								else if dp - up < 5 * 1 << 20
									r1.resume()
							100
						)
				r2.on "response", (response) ->
					Task.update userId: socket.userId, path: taskPath, {downloadProgress: 0, uploadProgress: 0}, (err, count) ->
					io.sockets.clients().filter((x) -> x.userId is socket.userId).forEach (x) -> x.volatile.emit "progress", taskPath: taskPath, download: 0, upload: 0
					clearInterval si


	socket.on "failureAck", ({taskPath}, callback) ->
		return callback success: false unless socket.userId?
		Task.update userId: socket.userId, path: taskPath, status: "post_failure", {$unset: status: ""}, (err, count) ->
			return callback: false unless count is 1
			callback success: true
			io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "failureAck", taskPath: taskPath

mongoose.connection.once "open", ->
	console.log "Connected to MongoDB"
	Task.update status: $in: ["posting", "transferring"], {status: "post_failure", $unset: downloadProgress: 0, uploadProgress: 0}, multi: true, (err, count) ->
		console.log err if err?
		console.log "#{count} tasks failed" if count > 0
		server.listen (port = process.env.PORT ? 5080), -> console.log "Listening on port #{port}"