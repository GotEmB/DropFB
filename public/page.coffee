require.config
	paths:
		jquery: "jquery/jquery-2.0.3.min"
		batman: "batmanjs/batman"
		bootstrap: "twitter/bootstrap.min"
		facebook: "//connect.facebook.net/en_US/all"
		dropbox: "//cdnjs.cloudflare.com/ajax/libs/dropbox.js/0.10.0/dropbox.min"
		socket_io: "socket.io/socket.io"
	shim:
		batman: deps: ["jquery"], exports: "Batman"
		bootstrap: deps: ["jquery"]
		facebook: exports: "FB"
		dropbox: exports: "Dropbox"
		socket_io: exports: "io"

define "Batman", ["batman"], (Batman) -> Batman.DOM.readers.batmantarget = Batman.DOM.readers.target and delete Batman.DOM.readers.target and Batman

require ["jquery", "Batman", "facebook", "dropbox", "socket_io", "bootstrap"], ($, Batman, FB, Dropbox, io) ->

	class User extends Batman.Model

	class AppContext extends Batman.Model
		@accessor "userLoggedIn", -> @get("currentUser") instanceof User
		@accessor "requireDbAuth", -> @get("userLoggedIn") and not @get("currentUser.dbAccessToken")?
		constructor: ->
			@set "pageLoading", "true"
			socket = undefined
			FB.init appId: "364692580326195", status: true
			Dropbox = new Dropbox.Client key: "wy7kcrp5mm8debj" #"do93enq2ux4ckd4"
			FB.Event.subscribe "auth.authResponseChange", @fbLoginStatusChanged = ({status: fbStatus, authResponse: fbAuthResponse}) =>
				return if @fbLoginStatusChanged.inProgress?
				@fbLoginStatusChanged.inProgress = true
				return if fbStatus is "connected" and @get "userLoggedIn"
				if fbStatus is "connected" and fbAuthResponse?
					FB.api "/me", (response2) =>
						@set "currentUser", new User
							name: response2.name
							userId: fbAuthResponse.userID
						socket = io.connect()
						socket.on "connect", =>
							socket.emit "handshake", userId: @get("userId"), ({dbAccessToken}) =>
								if dbAccessToken?
									do -> #...
								@set "pageLoading", false
								delete @fbLoginStatusChanged.inProgress
				else
					@unset "currentUser"
					socket?.disconnect()
					@set "pageLoading", false
				delete @fbLoginStatusChanged.inProgress
			FB.getLoginStatus @fbLoginStatusChanged
		fbLogin: ->
			FB.login()
		dbLogin: ->
			Dropbox.authenticate (error, client) =>
				console.log arguments

	class DropFB extends Batman.App
		@appContext: new AppContext

	DropFB.run()