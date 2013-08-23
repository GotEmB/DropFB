require.config
	paths:
		jquery: "jquery/jquery-2.0.3.min"
		batman: "batmanjs/batman"
		bootstrap: "//netdna.bootstrapcdn.com/bootstrap/3.0.0-wip/js/bootstrap.min"
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
	fbPermissions: ["user_photos", "photo_upload", "user_videos", "video_upload"]
	privacyOptions: EVERYONE: "Everyone", ALL_FRIENDS: "Friends", SELF: "Myself"

appContext = undefined

define "Batman", ["batman"], (Batman) -> Batman.DOM.readers.batmantarget = Batman.DOM.readers.target and delete Batman.DOM.readers.target and Batman

require ["jquery", "Batman", "facebook", "dropbox", "socket_io", "bootstrap"], ($, Batman, FB, Dropbox, io) ->

	class NewAlbum extends Batman.Model
		@accessor "notValid", -> not (@get("title")? and @get("title") isnt "")
		constructor: ->
			super
			@set "privacyOptions", new Batman.Set (new PrivacyOption value: key, label: value for key, value of constants.privacyOptions)...
			@set "selectedPrivacyOption", @get("privacyOptions").find (x) -> x.get("label") is "Friends"
		cancel: ->
			$("#newAlbumDialog").modal "hide"
		createAndUpload: ->
			FB.api "/me/albums", "post", name: @get("title"), message: @get("description"), privacy: value: @get("selectedPrivacyOption.value"), ({id, error}) =>
				if error?
					console.error error
				else
					appContext.get("albums").add newAlbum = new Album id: id, name: @get("title")
					newAlbum.delayedUploadTasks()
				$("#newAlbumDialog").modal "hide"

		class PrivacyOption extends Batman.Model
			@accessor "selected", -> appContext.get("newAlbum.selectedPrivacyOption") is @
			selectOption: -> appContext.set "newAlbum.selectedPrivacyOption", @

	class Album extends Batman.Model
		uploadTasks: ->
			appContext.get("selectedTasks").forEach (task) =>
				task.set "status", "posting"
				appContext.socket.emit "uploadTask", fbAccessToken: FB.getAuthResponse().accessToken, taskPath: task.get("path"), albumId: @get("id"), ({success}) =>
					task.set "status", if success then "post_success" else "post_failure"
		delayedUploadTasks: ->
			appContext.get("selectedTasks").forEach (task) =>
				task.set "status", "posting"
				appContext.socket.emit "uploadTask", fbAccessToken: FB.getAuthResponse().accessToken, taskPath: task.get("path"), albumId: @get("id"), delay: 3000, ({success}) =>
					task.set "status", if success then "post_success" else "post_failure"

	class User extends Batman.Model

	class Task extends Batman.Model
		@encode "path", "thumbnail", "type", "caption", "status", "downloadProgress", "uploadProgress"
		@accessor "isVideo", -> @get("type") is "video"
		@accessor "selectable", -> @get("status") not in ["posting", "post_success", "post_failure", "transferring"]
		@accessor "posting", -> @get("status") is "posting"
		@accessor "post_success", -> @get("status") is "post_success"
		@accessor "post_failure", -> @get("status") is "post_failure"
		@accessor "showStatus", -> @get("status")?
		@accessor "showProgress", -> @get("status") is "transferring" and (@get("downloadProgress") < 99.99 or @get("uploadProgress") < 99.99)
		@accessor "downloadPie", ->
			p = Number @get("downloadProgress") ? 0
			p = 99.99 if p > 99.99
			"""
				M 25 25
				L 25 10
				A 15 15 0 #{if p < 50 then 0 else 1} 1 #{25 + 15 * Math.sin p * Math.PI / 50} #{25 - 15 * Math.cos p * Math.PI / 50}
				Z
			"""
		@accessor "uploadPie", ->
			p = Number @get("uploadProgress") ? 0
			p = 99.99 if p > 99.99
			"""
				M 25 25
				L 25 10
				A 15 15 0 #{if p < 50 then 0 else 1} 1 #{25 + 15 * Math.sin p * Math.PI / 50} #{25 - 15 * Math.cos p * Math.PI / 50}
				Z
			"""
		constructor: ->
			super
			@set "selected", false
			@set "previewLoaded", false
			@observe "selectable", (value) -> @set "selected", false unless value
			@set "oldCaption", @get "caption"
		toggleSelection: ->
			if @get "selectable"
				@set "selected", not @get "selected"
			else if @get "post_success"
				appContext.socket.emit "removeTask", taskPath: @get("path"), ({success}) =>
					appContext.get("tasks").remove @ if success
			else if @get "post_failure"
				appContext.socket.emit "failureAck", taskPath: @get("path"), ({success}) =>
					@unset "status" if success
		imgOnLoad: ->
			@set "previewLoaded", true
		captionChanged: ->
			return if @get("caption") is @get "oldCaption"
			appContext.socket.emit "captionChanged", taskPath: @get("path"), caption: @get "caption"
			@set "oldCaption", @get "caption"

	class AppContext extends Batman.Model
		@accessor "userLoggedIn", -> @get("currentUser") instanceof User
		@accessor "selectedTasks", -> @get("tasks")?.filter (x) -> x.get "selected"
		@accessor "selectedTasksCount", -> @get("selectedTasks")?.length ? 0
		@accessor "noTasksSelected", -> @get("selectedTasksCount") is 0
		@accessor "allTasksSelected", -> @get("selectedTasksCount") is @get("tasks")?.filter((x) -> x.get "selectable").length ? 0
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
					fbPermissions = data?[0] ? {}
					if fbStatus is "connected" and fbAuthResponse? and constants.fbPermissions.every((x) -> fbPermissions[x] is 1)
						@socket = io.connect()
						@socket.on "connect", =>
							FB.api "/me", ({name}) =>
								FB.api "/me/albums?fields=name,can_upload", ({data: albums}) =>
									@set "albums", new Batman.Set albums.filter((x) -> x.can_upload).map((x) -> new Album id: x.id, name: x.name)...
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
						@socket.on "posting", ({taskPath}) =>
							@get("tasks").find((x) -> x.get("path") is taskPath)?.set "status", "posting"
						@socket.on "transferring", ({taskPath}) =>
							@get("tasks").find((x) -> x.get("path") is taskPath)?.set "status", "transferring"
						@socket.on "uploadedTask", ({taskPath, success}) =>
							@get("tasks").find((x) -> x.get("path") is taskPath)?.set "status", if success then "post_success" else "post_failure"
						@socket.on "failureAck", ({taskPath}) =>
							@get("tasks").find((x) -> x.get("path") is taskPath)?.unset "status"
						@socket.on "progress", ({taskPath, download, upload}) =>
							task = @get("tasks").find((x) -> x.get("path") is taskPath)
							task?.set "downloadProgress", download
							task?.set "uploadProgress", upload
					else
						@unset "currentUser"
						@socket?.disconnect()
						@set "pageLoading", false
						@unset "tasks"
						@unset "albums"
						delete @fbLoginStatusChanged.inProgress
			FB.getLoginStatus @fbLoginStatusChanged
			$('#myModal').on "hidden.bs.modal", => @unset "newAlbum"
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
			@get("tasks").forEach (x) -> x.set "selected", true if x.get "selectable"
		removeSelectedTasks: ->
			@get("selectedTasks").forEach (task) =>
				@socket.emit "removeTask", taskPath: task.get("path"), ({success}) =>
					@get("tasks").remove task if success
		uploadTasks: ->
			@get("selectedTasks").forEach (task) =>
				task.set "status", "posting"
				@socket.emit "uploadTask", fbAccessToken: FB.getAuthResponse().accessToken, taskPath: task.get("path"), ({success}) =>
					task.set "status", if success then "post_success" else "post_failure"
		createNewAlbum: ->
			@set "newAlbum", new NewAlbum
			$("#newAlbumDialog").modal "show"

	class DropFB extends Batman.App
		@appContext: appContext = new AppContext

	DropFB.run()

	$ ->
		$("#navbar2").affix offset: top: 65