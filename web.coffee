express = require "express"
http = require "http"
socket_io = require "socket.io"
request = require "request"
mongoose = require "mongoose"

currentDownloads = []

mongoose.connect "mongodb://#{process.env.MONGOUSER}:#{process.env.MONGOPASS}@ds037778.mongolab.com:37778/dropfbport"
User = mongoose.model "User", userId: String, dbAccessToken: String

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
		User.findOne userId: userId, (err, user) ->
			if user?
				callback dbAccessToken: user.dbAccessToken
			else
				callback {}

server.listen (port = process.env.PORT ? 5080), -> console.log "Listening on port #{port}"