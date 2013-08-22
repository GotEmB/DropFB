express = require "express"
http = require "http"
socket_io = require "socket.io"
request = require "request"

currentTasks = {}

expressServer = express()
expressServer.configure ->

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
io.set "log level", 0
io.sockets.on "connection", (socket) ->

	socket.on "handshake", ({userId}, callback) ->
		callback tasks: currentTasks[socket.userId = userId] ?= []

	socket.on "addTask", ({task}, callback) ->
		return callback success: false unless socket.userId?
		return callback success: false if currentTasks[socket.userId].some (x) -> x.path is task.path
		currentTasks[socket.userId].push task
		callback success: true
		io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "addTask", task: task

	socket.on "removeTask", ({taskPath}, callback) ->
		return callback success: false unless socket.userId?
		return callback success: false unless currentTasks[socket.userId].some (x) -> x.path is taskPath and x.status isnt "posting"
		currentTasks[socket.userId] = currentTasks[socket.userId].filter (x) -> x.path isnt taskPath
		callback success: true
		io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "removeTask", taskPath: taskPath

	socket.on "captionChanged", ({taskPath, caption}) ->
		return unless socket.userId?
		return unless currentTasks[socket.userId].some (x) -> x.path is taskPath and x.status not in ["posting", "post_success", "post_failure"]
		currentTasks[socket.userId].filter((x) -> x.path is taskPath)[0].caption = caption
		io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "captionChanged", taskPath: taskPath, caption: caption

	socket.on "uploadTask", ({taskPath, fbAccessToken, albumId, delay}, callback) ->
		return callback success: false unless socket.userId?
		return callback success: false unless currentTasks[socket.userId].some (x) -> x.path is taskPath
		task = currentTasks[socket.userId].filter((x) -> x.path is taskPath)[0]
		task.status = "posting"
		io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "posting", taskPath: taskPath
		if task.type is "photo"
			setTimeout(
				->
					request.post "https://graph.facebook.com/#{albumId ? socket.userId}/photos", form: access_token: fbAccessToken, url: taskPath, name: task.caption, (error, response, body) ->
						body = try JSON.parse body catch then body
						callback success: not (error? or body.error?)
						task.status = unless error? or body.error? then "post_success" else "post_failure"
						io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "uploadedTask", taskPath: taskPath, success: not (error? or body.error?)
				delay ? 0
			)
		else if task.type is "video"
			r2 = request.post "https://graph-video.facebook.com/me/videos"
			form = r2.form()
			form.append "access_token", fbAccessToken
			form.append "name", task.caption
			form.append "file", r1 = request.get taskPath
			si = undefined
			r1.on "response", (response) ->
				io.sockets.clients().filter((x) -> x.userId is socket.userId).forEach (x) -> x.emit "transferring", taskPath: taskPath
				console.log response
				fileSize = Number response.headers["content-length"]
				oldProgress = download: 0, upload: 0
				si = setInterval(
					->
						task.downloadProgress = r1.response?.connection.socket.bytesRead / fileSize * 100
						task.uploadProgress = r2.req.connection.socket._bytesDispatched / fileSize * 100
						return if oldProgress.download is task.downloadProgress and oldProgress.upload is task.uploadProgress
						oldProgress = download: task.downloadProgress, upload: task.uploadProgress
						io.sockets.clients().filter((x) -> x.userId is socket.userId).forEach (x) -> x.volatile.emit "progress", taskPath: taskPath, download: task.downloadProgress, upload: task.uploadProgress
					100
				)
			r2.on "response", (response) ->
				task.downloadProgress = task.uploadProgress = 0
				io.sockets.clients().filter((x) -> x.userId is socket.userId).forEach (x) -> x.volatile.emit "progress", taskPath: taskPath, download: 0, upload: 0
				console.log result: response
				clearInterval si
				callback success: true
				task.status = "post_success"
				io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "uploadedTask", taskPath: taskPath, success: true


	socket.on "failureAck", ({taskPath}, callback) ->
		return callback success: false unless socket.userId?
		return callback success: false unless currentTasks[socket.userId].some (x) -> x.path is taskPath
		io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "failureAck", taskPath: taskPath

server.listen (port = process.env.PORT ? 5080), -> console.log "Listening on port #{port}"