require.config
	paths:
		jquery: "jquery/jquery-2.0.3.min"
		batman: "batmanjs/batman"
		bootstrap: "twitter/bootstrap.min"
		facebook: "//connect.facebook.net/en_US/all"
	shim:
		batman: deps: ["jquery"], exports: "Batman"
		bootstrap: ["jquery"]
		facebook: exports: "FB"

require [
	"jquery"
	"batman"
	"facebook"
	# --- #
	"bootstrap"
], ($, Batman, FB) ->

	class User extends Batman.Model

	class AppContext extends Batman.Model
		@accessor "userLoggedIn", -> @get("currentUser") instanceof User
		constructor: ->
			FB.init appId: "364692580326195", status: true
			FB.Event.subscribe "auth.authResponseChange", (response1) =>
				console.log response1
				if response1.status is "connected" and response1.authResponse?
					FB.api "/me", (response2) =>
						@set "currentUser", new User
							name: response2.name
							accessToken: response1.authResponse.accessToken
							userId: response1.authResponse.userID
				else
					@unset "currentUser"
		login: ->
			FB.login()

	class DropFB extends Batman.App
		@appContext: new AppContext

	DropFB.run()