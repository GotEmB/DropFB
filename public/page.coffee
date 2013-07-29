require.config
	paths:
		jquery: "jquery/jquery-2.0.3.min"
		batman: "batmanjs/batman"
		bootstrap: "twitter/bootstrap.min"
		facebook: "//connect.facebook.net/en_US/all"
		dropbox: "//dropbox.com/static/api/1/dropins"
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

	class Task extends Batman.Model

	class AppContext extends Batman.Model
		@accessor "userLoggedIn", -> @get("currentUser") instanceof User
		constructor: ->
			@set "pageLoading", "true"
			socket = undefined
			FB.init appId: "364692580326195", status: true
			Dropbox.appKey = "wy7kcrp5mm8debj"
			FB.Event.subscribe "auth.authResponseChange", @fbLoginStatusChanged = ({status: fbStatus, authResponse: fbAuthResponse}) =>
				return if @fbLoginStatusChanged.inProgress?
				@fbLoginStatusChanged.inProgress = true
				return if fbStatus is "connected" and @get "userLoggedIn"
				if fbStatus is "connected" and fbAuthResponse?
					FB.api "/me", (response2) =>
						socket = io.connect()
						socket.on "connect", =>
							socket.emit "handshake", userId: @get("userId"), ({tasks}) =>
								@set "currentUser", new User name: response2.name, userId: fbAuthResponse.userID
								@set "tasks", new Batman.Set
								#...
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
		dbChooseFiles: ->
			Dropbox.choose linkType: "direct", multiselect: true, success: (files) =>
				for file in files when file.thumbnails? and file.bytes < 1 << 30 and not @get("tasks").find((x) => x.path is file.link)?
					@get("tasks").add new Task path: file.link, thumbnail: file.thumbnails["200x200"]

	class DropFB extends Batman.App
		@appContext: new AppContext

	DropFB.run()