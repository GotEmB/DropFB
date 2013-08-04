require.config
	paths:
		jquery: "jquery/jquery-2.0.3.min"
		batman: "batmanjs/batman"
		bootstrap: "//netdna.bootstrapcdn.com/bootstrap/3.0.0-rc1/js/bootstrap.min"
		facebook: "//connect.facebook.net/en_US/all"
		dropbox: "//dropbox.com/static/api/1/dropins"
		socket_io: "socket.io/socket.io"
	shim:
		batman: deps: ["jquery"], exports: "Batman"
		bootstrap: deps: ["jquery"]
		facebook: exports: "FB"
		dropbox: exports: "Dropbox"
		socket_io: exports: "io"

videoFormats = ["3g2", "3gp", "3gpp", "asf", "avi", "dat", "divx", "dv", "f4v", "flv", "m2ts", "m4v", "mkv", "mod", "mov", "mp4", "mpe", "mpeg", "mpeg4", "mpg", "mts", "nsv", "ogm", "ogv", "qt", "tod", "ts", "vob", "wmv"]

define "Batman", ["batman"], (Batman) -> Batman.DOM.readers.batmantarget = Batman.DOM.readers.target and delete Batman.DOM.readers.target and Batman

require ["jquery", "Batman", "facebook", "dropbox", "socket_io", "bootstrap"], ($, Batman, FB, Dropbox, io) ->

	class User extends Batman.Model

	class Task extends Batman.Model
		@encode "path", "thumbnail", "type"
		@accessor "isVideo", -> @get("type") is "video"
		constructor: ->
			super
			@set "selected", false
			@set "previewLoaded", false

		toggleSelection: ->
			@set "selected", not @get "selected"
		imgOnLoad: ->
			@set "previewLoaded", true

	class AppContext extends Batman.Model
		@accessor "userLoggedIn", -> @get("currentUser") instanceof User
		@accessor "selectedTasks", -> @get("tasks")?.filter (x) -> x.get "selected"
		@accessor "selectedTasksCount", -> @get("selectedTasks")?.length ? 0
		@accessor "noTasksSelected", -> @get("selectedTasksCount") is 0
		@accessor "allTasksSelected", -> @get("selectedTasksCount") is @get "tasks.length"
		@accessor "aVideoTaskSelected", -> @get("selectedTasks")?.some (x) -> x.get "isVideo"
		constructor: ->
			super
			@set "pageLoading", "true"
			FB.init appId: "364692580326195", status: true
			Dropbox.appKey = "wy7kcrp5mm8debj"
			FB.Event.subscribe "auth.authResponseChange", @fbLoginStatusChanged = ({status: fbStatus, authResponse: fbAuthResponse}) =>
				return if @fbLoginStatusChanged.inProgress?
				@fbLoginStatusChanged.inProgress = true
				return if fbStatus is "connected" and @get "userLoggedIn"
				if fbStatus is "connected" and fbAuthResponse?
					FB.api "/me", (response2) =>
						@socket = io.connect()
						@socket.on "connect", =>
							@socket.emit "handshake", userId: fbAuthResponse.userID, ({tasks}) =>
								@set "currentUser", new User name: response2.name, userId: fbAuthResponse.userID
								@set "tasks", new Batman.Set
								@get("tasks").add (new Task task for task in tasks)...
								@set "pageLoading", false
								delete @fbLoginStatusChanged.inProgress
						@socket.on "addTask", ({task}) =>
							@get("tasks").add new Task task
						@socket.on "removeTask", ({taskPath}) =>
							@get("tasks").remove @get("tasks").find (x) -> x.get("path") is taskPath
				else
					@unset "currentUser"
					@socket?.disconnect()
					@set "pageLoading", false
					@unset "tasks"
					delete @fbLoginStatusChanged.inProgress
			FB.getLoginStatus @fbLoginStatusChanged
		fbLogin: ->
			FB.login()
		dbChooseFiles: ->
			Dropbox.choose linkType: "direct", multiselect: true, success: (files) =>
				for file in files when JSON.stringify(file.thumbnails) not in [undefined, "null", "{}"] and file.bytes < 1 << 30 and not @get("tasks").find((x) => x.get("path") is file.link)? then do (file) =>
					task = new Task
						path: file.link
						thumbnail: file.thumbnails["640x480"]
						type: if file.name.toLowerCase().match(/[a-z0-9]+$/g)[0] in videoFormats then "video" else "photo"
					@socket.emit "addTask", task: task.toJSON(), ({success}) =>
						@get("tasks").add task if success
		unselectAllTasks: ->
			@get("tasks").forEach (x) -> x.set "selected", false
		selectAllTasks: ->
			@get("tasks").forEach (x) -> x.set "selected", true
		removeSelectedTasks: ->
			@get("selectedTasks").forEach (task) =>
				@socket.emit "removeTask", taskPath: task.get("path"), ({success}) =>
					@get("tasks").remove task if success

	class DropFB extends Batman.App
		@appContext: new AppContext

	DropFB.run()

	$ ->
		$("#navbar2").affix offset: top: 75