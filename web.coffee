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
		return callback success: false unless currentTasks[socket.userId].some (x) -> x.path is taskPath
		currentTasks[socket.userId] = currentTasks[socket.userId].filter (x) -> x.path isnt taskPath
		callback success: true
		io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "removeTask", taskPath: taskPath

	socket.on "captionChanged", ({taskPath, caption}) ->
		return unless socket.userId?
		return unless currentTasks[socket.userId].some (x) -> x.path is taskPath
		currentTasks[socket.userId].filter((x) -> x.path is taskPath)[0].caption = caption
		io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "captionChanged", taskPath: taskPath, caption: caption

	socket.on "descriptionChanged", ({taskPath, description}) ->
		return unless socket.userId?
		return unless currentTasks[socket.userId].some (x) -> x.path is taskPath
		currentTasks[socket.userId].filter((x) -> x.path is taskPath)[0].description = description
		io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "descriptionChanged", taskPath: taskPath, description: description

	socket.on "uploadTask", ({taskPath, fbAccessToken}, callback) ->
		return callback success: false unless socket.userId?
		return callback success: false unless currentTasks[socket.userId].some (x) -> x.path is taskPath
		request.post "https://graph.facebook.com/#{socket.userId}/photos", form: access_token: fbAccessToken, url: taskPath, (error, response, body) ->
			console.log access_token: fbAccessToken, request: response.request, body: body
			callback success: true
			io.sockets.clients().filter((x) -> x isnt socket and x.userId is socket.userId).forEach (x) -> x.emit "uploadedTask", taskPath: taskPath, success: true

server.listen (port = process.env.PORT ? 5080), -> console.log "Listening on port #{port}"