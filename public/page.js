// Generated by CoffeeScript 1.6.3
var appContext, constants,
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

require.config({
  paths: {
    jquery: "jquery/jquery-2.0.3.min",
    batman: "batmanjs/batman",
    bootstrap: "//netdna.bootstrapcdn.com/bootstrap/3.0.0-wip/js/bootstrap.min",
    facebook: "//connect.facebook.net/en_US/all",
    dropbox: "//dropbox.com/static/api/1/dropins",
    socket_io: "socket.io/socket.io"
  },
  shim: {
    batman: {
      deps: ["jquery"],
      exports: "Batman"
    },
    bootstrap: {
      deps: ["jquery"]
    },
    facebook: {
      exports: "FB"
    },
    dropbox: {
      exports: "Dropbox"
    },
    socket_io: {
      exports: "io"
    }
  }
});

constants = {
  videoFormats: ["3g2", "3gp", "3gpp", "asf", "avi", "dat", "divx", "dv", "f4v", "flv", "m2ts", "m4v", "mkv", "mod", "mov", "mp4", "mpe", "mpeg", "mpeg4", "mpg", "mts", "nsv", "ogm", "ogv", "qt", "tod", "ts", "vob", "wmv"],
  fbPermissions: ["user_photos", "photo_upload", "user_videos", "video_upload"],
  privacyOptions: {
    EVERYONE: "Everyone",
    ALL_FRIENDS: "Friends",
    SELF: "Myself"
  }
};

appContext = void 0;

define("Batman", ["batman"], function(Batman) {
  return Batman.DOM.readers.batmantarget = Batman.DOM.readers.target && delete Batman.DOM.readers.target && Batman;
});

require(["jquery", "Batman", "facebook", "dropbox", "socket_io", "bootstrap"], function($, Batman, FB, Dropbox, io) {
  var Album, AppContext, DropFB, NewAlbum, Task, User, _ref, _ref1, _ref2;
  NewAlbum = (function(_super) {
    var PrivacyOption, _ref;

    __extends(NewAlbum, _super);

    NewAlbum.accessor("notValid", function() {
      return !((this.get("title") != null) && this.get("title") !== "");
    });

    function NewAlbum() {
      var key, value;
      NewAlbum.__super__.constructor.apply(this, arguments);
      this.set("privacyOptions", (function(func, args, ctor) {
        ctor.prototype = func.prototype;
        var child = new ctor, result = func.apply(child, args);
        return Object(result) === result ? result : child;
      })(Batman.Set, (function() {
        var _ref, _results;
        _ref = constants.privacyOptions;
        _results = [];
        for (key in _ref) {
          value = _ref[key];
          _results.push(new PrivacyOption({
            value: key,
            label: value
          }));
        }
        return _results;
      })(), function(){}));
      this.set("selectedPrivacyOption", this.get("privacyOptions").find(function(x) {
        return x.get("label") === "Friends";
      }));
    }

    NewAlbum.prototype.cancel = function() {
      return $("#newAlbumDialog").modal("hide");
    };

    NewAlbum.prototype.createAndUpload = function() {
      var _this = this;
      return FB.api("/me/albums", "post", {
        name: this.get("title"),
        message: this.get("description"),
        privacy: {
          value: this.get("selectedPrivacyOption.value")
        }
      }, function(_arg) {
        var error, id, newAlbum;
        id = _arg.id, error = _arg.error;
        if (error != null) {
          console.error(error);
        } else {
          appContext.get("albums").add(newAlbum = new Album({
            id: id,
            name: _this.get("title")
          }));
          newAlbum.delayedUploadTasks();
        }
        return $("#newAlbumDialog").modal("hide");
      });
    };

    PrivacyOption = (function(_super1) {
      __extends(PrivacyOption, _super1);

      function PrivacyOption() {
        _ref = PrivacyOption.__super__.constructor.apply(this, arguments);
        return _ref;
      }

      PrivacyOption.accessor("selected", function() {
        return appContext.get("newAlbum.selectedPrivacyOption") === this;
      });

      PrivacyOption.prototype.selectOption = function() {
        return appContext.set("newAlbum.selectedPrivacyOption", this);
      };

      return PrivacyOption;

    })(Batman.Model);

    return NewAlbum;

  }).call(this, Batman.Model);
  Album = (function(_super) {
    __extends(Album, _super);

    function Album() {
      _ref = Album.__super__.constructor.apply(this, arguments);
      return _ref;
    }

    Album.prototype.uploadTasks = function() {
      var _this = this;
      return appContext.get("selectedTasks").forEach(function(task) {
        task.set("status", "posting");
        return appContext.socket.emit("uploadTask", {
          fbAccessToken: FB.getAuthResponse().accessToken,
          taskPath: task.get("path"),
          albumId: _this.get("id")
        }, function(_arg) {
          var success;
          success = _arg.success;
          return task.set("status", success ? "post_success" : "post_failure");
        });
      });
    };

    Album.prototype.delayedUploadTasks = function() {
      var _this = this;
      return appContext.get("selectedTasks").forEach(function(task) {
        task.set("status", "posting");
        return appContext.socket.emit("uploadTask", {
          fbAccessToken: FB.getAuthResponse().accessToken,
          taskPath: task.get("path"),
          albumId: _this.get("id"),
          delay: 3000
        }, function(_arg) {
          var success;
          success = _arg.success;
          return task.set("status", success ? "post_success" : "post_failure");
        });
      });
    };

    return Album;

  })(Batman.Model);
  User = (function(_super) {
    __extends(User, _super);

    function User() {
      _ref1 = User.__super__.constructor.apply(this, arguments);
      return _ref1;
    }

    return User;

  })(Batman.Model);
  Task = (function(_super) {
    __extends(Task, _super);

    Task.encode("path", "thumbnail", "type", "caption", "status");

    Task.accessor("isVideo", function() {
      return this.get("type") === "video";
    });

    Task.accessor("selectable", function() {
      var _ref2;
      return (_ref2 = this.get("status")) !== "posting" && _ref2 !== "post_success" && _ref2 !== "post_failure";
    });

    Task.accessor("posting", function() {
      return this.get("status") === "posting";
    });

    Task.accessor("post_success", function() {
      return this.get("status") === "post_success";
    });

    Task.accessor("post_failure", function() {
      return this.get("status") === "post_failure";
    });

    Task.accessor("showStatus", function() {
      return this.get("status") != null;
    });

    function Task() {
      Task.__super__.constructor.apply(this, arguments);
      this.set("selected", false);
      this.set("previewLoaded", false);
      this.observe("selectable", function(value) {
        if (!value) {
          return this.set("selected", false);
        }
      });
    }

    Task.prototype.toggleSelection = function() {
      var _this = this;
      if (this.get("selectable")) {
        return this.set("selected", !this.get("selected"));
      } else if (this.get("post_success")) {
        return appContext.socket.emit("removeTask", {
          taskPath: this.get("path")
        }, function(_arg) {
          var success;
          success = _arg.success;
          if (success) {
            return appContext.get("tasks").remove(_this);
          }
        });
      } else if (this.get("post_failure")) {
        return appContext.socket.emit("failureAck", {
          taskPath: this.get("path")
        }, function(_arg) {
          var success;
          success = _arg.success;
          return _this.unset("status");
        });
      }
    };

    Task.prototype.imgOnLoad = function() {
      return this.set("previewLoaded", true);
    };

    Task.prototype.captionChanged = function() {
      return appContext.socket.emit("captionChanged", {
        taskPath: this.get("path"),
        caption: this.get("caption")
      });
    };

    return Task;

  })(Batman.Model);
  AppContext = (function(_super) {
    __extends(AppContext, _super);

    AppContext.accessor("userLoggedIn", function() {
      return this.get("currentUser") instanceof User;
    });

    AppContext.accessor("selectedTasks", function() {
      var _ref2;
      return (_ref2 = this.get("tasks")) != null ? _ref2.filter(function(x) {
        return x.get("selected");
      }) : void 0;
    });

    AppContext.accessor("selectedTasksCount", function() {
      var _ref2, _ref3;
      return (_ref2 = (_ref3 = this.get("selectedTasks")) != null ? _ref3.length : void 0) != null ? _ref2 : 0;
    });

    AppContext.accessor("noTasksSelected", function() {
      return this.get("selectedTasksCount") === 0;
    });

    AppContext.accessor("allTasksSelected", function() {
      return this.get("selectedTasksCount") === this.get("tasks.length");
    });

    AppContext.accessor("aVideoTaskSelected", function() {
      var _ref2;
      return (_ref2 = this.get("selectedTasks")) != null ? _ref2.some(function(x) {
        return x.get("isVideo");
      }) : void 0;
    });

    function AppContext() {
      var _this = this;
      AppContext.__super__.constructor.apply(this, arguments);
      this.set("pageLoading", "true");
      FB.init({
        appId: "364692580326195",
        status: true
      });
      Dropbox.appKey = "wy7kcrp5mm8debj";
      FB.Event.subscribe("auth.authResponseChange", this.fbLoginStatusChanged = function(_arg) {
        var fbAuthResponse, fbStatus;
        fbStatus = _arg.status, fbAuthResponse = _arg.authResponse;
        if (_this.fbLoginStatusChanged.inProgress != null) {
          return;
        }
        _this.fbLoginStatusChanged.inProgress = true;
        if (fbStatus === "connected" && _this.get("userLoggedIn")) {
          return;
        }
        return FB.api("/me/permissions", function(_arg1) {
          var data, fbPermissions, _ref2, _ref3;
          data = _arg1.data;
          fbPermissions = (_ref2 = data != null ? data[0] : void 0) != null ? _ref2 : {};
          if (fbStatus === "connected" && (fbAuthResponse != null) && constants.fbPermissions.every(function(x) {
            return fbPermissions[x] === 1;
          })) {
            _this.socket = io.connect();
            _this.socket.on("connect", function() {
              return FB.api("/me", function(_arg2) {
                var name;
                name = _arg2.name;
                FB.api("/me/albums?fields=name,can_upload", function(_arg3) {
                  var albums;
                  albums = _arg3.data;
                  return _this.set("albums", (function(func, args, ctor) {
                    ctor.prototype = func.prototype;
                    var child = new ctor, result = func.apply(child, args);
                    return Object(result) === result ? result : child;
                  })(Batman.Set, albums.filter(function(x) {
                    return x.can_upload;
                  }).map(function(x) {
                    return new Album({
                      id: x.id,
                      name: x.name
                    });
                  }), function(){}));
                });
                return _this.socket.emit("handshake", {
                  userId: fbAuthResponse.userID
                }, function(_arg3) {
                  var task, tasks, _ref3;
                  tasks = _arg3.tasks;
                  _this.set("currentUser", new User({
                    name: name,
                    userId: fbAuthResponse.userID
                  }));
                  _this.set("tasks", new Batman.Set);
                  (_ref3 = _this.get("tasks")).add.apply(_ref3, (function() {
                    var _i, _len, _results;
                    _results = [];
                    for (_i = 0, _len = tasks.length; _i < _len; _i++) {
                      task = tasks[_i];
                      _results.push(new Task(task));
                    }
                    return _results;
                  })());
                  _this.set("pageLoading", false);
                  return delete _this.fbLoginStatusChanged.inProgress;
                });
              });
            });
            _this.socket.on("addTask", function(_arg2) {
              var task;
              task = _arg2.task;
              return _this.get("tasks").add(new Task(task));
            });
            _this.socket.on("removeTask", function(_arg2) {
              var taskPath;
              taskPath = _arg2.taskPath;
              return _this.get("tasks").remove(_this.get("tasks").find(function(x) {
                return x.get("path") === taskPath;
              }));
            });
            _this.socket.on("captionChanged", function(_arg2) {
              var caption, taskPath, _ref3;
              taskPath = _arg2.taskPath, caption = _arg2.caption;
              return (_ref3 = _this.get("tasks").find(function(x) {
                return x.get("path") === taskPath;
              })) != null ? _ref3.set("caption", caption) : void 0;
            });
            _this.socket.on("posting", function(_arg2) {
              var taskPath, _ref3;
              taskPath = _arg2.taskPath;
              return (_ref3 = _this.get("tasks").find(function(x) {
                return x.get("path") === taskPath;
              })) != null ? _ref3.set("status", "posting") : void 0;
            });
            _this.socket.on("uploadedTask", function(_arg2) {
              var success, taskPath, _ref3;
              taskPath = _arg2.taskPath, success = _arg2.success;
              return (_ref3 = _this.get("tasks").find(function(x) {
                return x.get("path") === taskPath;
              })) != null ? _ref3.set("status", success ? "post_success" : "post_failure") : void 0;
            });
            return _this.socket.on("failureAck", function(_arg2) {
              var taskPath, _ref3;
              taskPath = _arg2.taskPath;
              return (_ref3 = _this.get("tasks").find(function(x) {
                return x.get("path") === taskPath;
              })) != null ? _ref3.unset("status") : void 0;
            });
          } else {
            _this.unset("currentUser");
            if ((_ref3 = _this.socket) != null) {
              _ref3.disconnect();
            }
            _this.set("pageLoading", false);
            _this.unset("tasks");
            _this.unset("albums");
            return delete _this.fbLoginStatusChanged.inProgress;
          }
        });
      });
      FB.getLoginStatus(this.fbLoginStatusChanged);
      $('#myModal').on("hidden.bs.modal", function() {
        return _this.unset("newAlbum");
      });
    }

    AppContext.prototype.fbLogin = function() {
      return FB.login((function() {}), {
        scope: constants.fbPermissions.join(",")
      });
    };

    AppContext.prototype.dbChooseFiles = function() {
      var _this = this;
      return Dropbox.choose({
        linkType: "direct",
        multiselect: true,
        success: function(files) {
          var file, _i, _len, _ref2, _results;
          _results = [];
          for (_i = 0, _len = files.length; _i < _len; _i++) {
            file = files[_i];
            if (((_ref2 = JSON.stringify(file.thumbnails)) !== (void 0) && _ref2 !== "null" && _ref2 !== "{}") && file.bytes < 1 << 30 && (_this.get("tasks").find(function(x) {
              return x.get("path") === file.link;
            }) == null)) {
              _results.push((function(file) {
                var task, _ref3;
                task = new Task({
                  path: file.link,
                  thumbnail: file.thumbnails["640x480"],
                  type: (_ref3 = file.name.toLowerCase().match(/[a-z0-9]+$/g)[0], __indexOf.call(constants.videoFormats, _ref3) >= 0) ? "video" : "photo"
                });
                return _this.socket.emit("addTask", {
                  task: task.toJSON()
                }, function(_arg) {
                  var success;
                  success = _arg.success;
                  if (success) {
                    return _this.get("tasks").add(task);
                  }
                });
              })(file));
            }
          }
          return _results;
        }
      });
    };

    AppContext.prototype.unselectAllTasks = function() {
      return this.get("tasks").forEach(function(x) {
        return x.set("selected", false);
      });
    };

    AppContext.prototype.selectAllTasks = function() {
      return this.get("tasks").forEach(function(x) {
        return x.set("selected", true);
      });
    };

    AppContext.prototype.removeSelectedTasks = function() {
      var _this = this;
      return this.get("selectedTasks").forEach(function(task) {
        return _this.socket.emit("removeTask", {
          taskPath: task.get("path")
        }, function(_arg) {
          var success;
          success = _arg.success;
          if (success) {
            return _this.get("tasks").remove(task);
          }
        });
      });
    };

    AppContext.prototype.uploadTasks = function() {
      var _this = this;
      return this.get("selectedTasks").forEach(function(task) {
        task.set("status", "posting");
        return _this.socket.emit("uploadTask", {
          fbAccessToken: FB.getAuthResponse().accessToken,
          taskPath: task.get("path")
        }, function(_arg) {
          var success;
          success = _arg.success;
          return task.set("status", success ? "post_success" : "post_failure");
        });
      });
    };

    AppContext.prototype.createNewAlbum = function() {
      this.set("newAlbum", new NewAlbum);
      return $("#newAlbumDialog").modal("show");
    };

    return AppContext;

  })(Batman.Model);
  DropFB = (function(_super) {
    __extends(DropFB, _super);

    function DropFB() {
      _ref2 = DropFB.__super__.constructor.apply(this, arguments);
      return _ref2;
    }

    DropFB.appContext = appContext = new AppContext;

    return DropFB;

  })(Batman.App);
  DropFB.run();
  return $(function() {
    return $("#navbar2").affix({
      offset: {
        top: 65
      }
    });
  });
});

/*
//@ sourceMappingURL=page.map
*/
