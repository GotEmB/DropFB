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

constants =
	videoFormats: ["3g2", "3gp", "3gpp", "asf", "avi", "dat", "divx", "dv", "f4v", "flv", "m2ts", "m4v", "mkv", "mod", "mov", "mp4", "mpe", "mpeg", "mpeg4", "mpg", "mts", "nsv", "ogm", "ogv", "qt", "tod", "ts", "vob", "wmv"]
	fbPermissions: ["user_photos", "photo_upload"]

appContext = undefined

define "Batman", ["batman"], (Batman) -> Batman.DOM.readers.batmantarget = Batman.DOM.readers.target and delete Batman.DOM.readers.target and Batman

require ["jquery", "Batman", "facebook", "dropbox", "socket_io", "bootstrap"], ($, Batman, FB, Dropbox, io) ->

	class User extends Batman.Model

	class Task extends Batman.Model
		@encode "path", "thumbnail", "type", "caption", "description"
		@accessor "isVideo", -> @get("type") is "video"
		constructor: ->
			super
			@set "selected", false
			@set "previewLoaded", false
		toggleSelection: ->
			@set "selected", not @get "selected"
		imgOnLoad: ->
			@set "previewLoaded", true
		captionChanged: ->
			appContext.socket.emit "captionChanged", taskPath: @get("path"), caption: @get "caption"
		descriptionChanged: ->
			appContext.socket.emit "descriptionChanged", taskPath: @get("path"), description: @get "description"

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
				FB.api "/me/permissions", ({data}) =>
					fbPermissions = data[0] ? {}
					if fbStatus is "connected" and fbAuthResponse? and constants.fbPermissions.every((x) -> fbPermissions[x] is 1)
						@socket = io.connect()
						@socket.on "connect", =>
							FB.api "/me", ({name}) =>
								FB.api "/me/albums?fields=name,can_upload", ({data: albums}) =>
									@set "albums", new Batman.Set albums.filter((x) -> x.can_upload).map((x) -> id: x.id, name: x.name)...
								@socket.emit "handshake", userId: fbAuthResponse.userID, ({tasks}) =>
									@set "currentUser", new User name: name, userId: fbAuthResponse.userID
									@set "tasks", new Batman.Set
									@get("tasks").add (new Task task for task in tasks)...
									@set "pageLoading", false
									delete @fbLoginStatusChanged.inProgress
						@socket.on "addTask", ({task}) =>
							@get("tasks").add new Task task
						@socket.on "removeTask", ({taskPath}) =>
							@get("tasks").remove @get("tasks").find (x) -> x.get("path") is taskPath
						@socket.on "captionChanged", ({taskPath, caption}) =>
							@get("tasks").find((x) -> x.get("path") is taskPath)?.set "caption", caption
						@socket.on "descriptionChanged", ({taskPath, description}) =>
							@get("tasks").find((x) -> x.get("path") is taskPath)?.set "description", description if taskPath is @get "path"
					else
						@unset "currentUser"
						@socket?.disconnect()
						@set "pageLoading", false
						@unset "tasks"
						@unset "albums"
						delete @fbLoginStatusChanged.inProgress
			FB.getLoginStatus @fbLoginStatusChanged
		fbLogin: ->
			FB.login (->), scope: constants.fbPermissions.join ","
		dbChooseFiles: ->
			Dropbox.choose linkType: "direct", multiselect: true, success: (files) =>
				for file in files when JSON.stringify(file.thumbnails) not in [undefined, "null", "{}"] and file.bytes < 1 << 30 and not @get("tasks").find((x) => x.get("path") is file.link)? then do (file) =>
					task = new Task
						path: file.link
						thumbnail: file.thumbnails["640x480"]
						type: if file.name.toLowerCase().match(/[a-z0-9]+$/g)[0] in constants.videoFormats then "video" else "photo"
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
		uploadTask: ->
			@get("selectedTasks").forEach (task) =>
				@socket.emit "uploadTask", fbAccessToken: FB.getAuthResponse.accessToken, taskPath: task.get "path" #...

	class DropFB extends Batman.App
		@appContext: appContext = new AppContext

	DropFB.run()

	$ ->
		$("#navbar2").affix offset: top: 75