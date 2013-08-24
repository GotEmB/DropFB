// Generated by CoffeeScript 1.6.3
var Task, currentTasks, express, expressServer, http, io, mongoose, request, server, socket_io;

express = require("express");

http = require("http");

socket_io = require("socket.io");

request = require("request");

mongoose = require("mongoose");

mongoose.connect(process.env.MONGODBSTR);

mongoose.connection.once("error", function() {
  console.error(arguments);
  return process.exit(1);
});

Task = mongoose.model("Task", {
  userId: String,
  path: String,
  thumbnail: String,
  type: String,
  caption: String,
  status: String,
  downloadProgress: Number,
  uploadProgress: Number
});

currentTasks = {};

expressServer = express();

expressServer.configure(function() {
  expressServer.use(express.compress());
  expressServer.use(express.bodyParser());
  expressServer.use(function(req, res, next) {
    req.url = (function() {
      switch (req.url) {
        case "/":
          return "/page.html";
        default:
          return req.url;
      }
    })();
    return next();
  });
  expressServer.use(express["static"]("" + __dirname + "/public", {
    maxAge: 0
  }, function(err) {
    return console.log("Static: " + err);
  }));
  return expressServer.use(expressServer.router);
});

server = http.createServer(expressServer);

io = socket_io.listen(server);

io.configure(function() {
  io.set("log level", 0);
  io.set("transports", ["xhr-polling"]);
  return io.set("polling duration", 10);
});

io.sockets.on("connection", function(socket) {
  socket.on("handshake", function(_arg, callback) {
    var userId;
    userId = _arg.userId;
    socket.userId = userId;
    return Task.find({
      userId: socket.userId
    }, function(err, tasks) {
      return callback({
        tasks: tasks
      });
    });
  });
  socket.on("addTask", function(_arg, callback) {
    var task;
    task = _arg.task;
    if (socket.userId == null) {
      return callback({
        success: false
      });
    }
    return Task.count({
      userId: socket.userId,
      path: task.path
    }, function(err, count) {
      if (count !== 0) {
        return callback({
          success: false
        });
      }
      task = new Task(task);
      task.userId = socket.userId;
      return task.save(function(err, task) {
        callback({
          success: true
        });
        return io.sockets.clients().filter(function(x) {
          return x !== socket && x.userId === socket.userId;
        }).forEach(function(x) {
          return x.emit("addTask", {
            task: task
          });
        });
      });
    });
  });
  socket.on("removeTask", function(_arg, callback) {
    var taskPath;
    taskPath = _arg.taskPath;
    if (socket.userId == null) {
      return callback({
        success: false
      });
    }
    return Task.remove({
      userId: socket.userId,
      path: taskPath,
      status: {
        $nin: ["posting", "transferring"]
      }
    }, function(err, count) {
      if (count !== 1) {
        return callback({
          success: false
        });
      }
      callback({
        success: true
      });
      return io.sockets.clients().filter(function(x) {
        return x !== socket && x.userId === socket.userId;
      }).forEach(function(x) {
        return x.emit("removeTask", {
          taskPath: taskPath
        });
      });
    });
  });
  socket.on("captionChanged", function(_arg) {
    var caption, taskPath;
    taskPath = _arg.taskPath, caption = _arg.caption;
    if (socket.userId == null) {
      return;
    }
    return Task.update({
      userId: socket.userId,
      path: taskPath,
      status: {
        $nin: ["posting", "post_success", "post_failure", "transferring"]
      }
    }, {
      caption: caption
    }, function(err, count) {
      if (count !== 1) {
        return;
      }
      return io.sockets.clients().filter(function(x) {
        return x !== socket && x.userId === socket.userId;
      }).forEach(function(x) {
        return x.emit("captionChanged", {
          taskPath: taskPath,
          caption: caption
        });
      });
    });
  });
  socket.on("uploadTask", function(_arg, callback) {
    var albumId, delay, fbAccessToken, taskPath;
    taskPath = _arg.taskPath, fbAccessToken = _arg.fbAccessToken, albumId = _arg.albumId, delay = _arg.delay;
    if (socket.userId == null) {
      return callback({
        success: false
      });
    }
    return Task.findOneAndUpdate({
      userId: socket.userId,
      path: taskPath,
      status: {
        $nin: ["posting", "post_success", "post_failure", "transferring"]
      }
    }, {
      status: "posting"
    }, function(err, task) {
      var form, r1, r2, si, _ref;
      if (task == null) {
        return callback({
          success: false
        });
      }
      io.sockets.clients().filter(function(x) {
        return x !== socket && x.userId === socket.userId;
      }).forEach(function(x) {
        return x.emit("posting", {
          taskPath: taskPath
        });
      });
      if (task.type === "photo") {
        return setTimeout(function() {
          return request.post("https://graph.facebook.com/" + (albumId != null ? albumId : socket.userId) + "/photos", {
            form: {
              access_token: fbAccessToken,
              url: taskPath,
              name: task.caption
            }
          }, function(error, response, body) {
            body = (function() {
              try {
                return JSON.parse(body);
              } catch (_error) {
                return body;
              }
            })();
            return Task.update({
              userId: socket.userId,
              path: taskPath
            }, {
              status: !((error != null) || (body.error != null)) ? "post_success" : "post_failure"
            }, function(err, count) {
              callback({
                success: !((error != null) || (body.error != null))
              });
              return io.sockets.clients().filter(function(x) {
                return x !== socket && x.userId === socket.userId;
              }).forEach(function(x) {
                return x.emit("uploadedTask", {
                  taskPath: taskPath,
                  success: !((error != null) || (body.error != null))
                });
              });
            });
          });
        }, delay != null ? delay : 0);
      } else if (task.type === "video") {
        r2 = request.post("https://graph-video.facebook.com/me/videos", function(error, response, body) {
          body = (function() {
            try {
              return JSON.parse(body);
            } catch (_error) {
              return body;
            }
          })();
          return Task.update({
            userId: socket.userId,
            path: taskPath
          }, {
            status: !((error != null) || (body.error != null)) ? "post_success" : "post_failure"
          }, function(err, count) {
            callback({
              success: !((error != null) || (body.error != null))
            });
            return io.sockets.clients().filter(function(x) {
              return x !== socket && x.userId === socket.userId;
            }).forEach(function(x) {
              return x.emit("uploadedTask", {
                taskPath: taskPath,
                success: !((error != null) || (body.error != null))
              });
            });
          });
        });
        form = r2.form();
        form.append("access_token", fbAccessToken);
        form.append("title", (_ref = task.caption) != null ? _ref : "");
        form.append("file", r1 = request.get(taskPath));
        si = void 0;
        r1.on("response", function(response) {
          return Task.update({
            userId: socket.userId,
            path: taskPath
          }, {
            status: "transferring"
          }, function(err, count) {
            var fileSize, oldProgress;
            io.sockets.clients().filter(function(x) {
              return x.userId === socket.userId;
            }).forEach(function(x) {
              return x.emit("transferring", {
                taskPath: taskPath
              });
            });
            fileSize = Number(response.headers["content-length"]);
            oldProgress = {
              download: 0,
              upload: 0
            };
            return si = setInterval(function() {
              var downloadProgress, uploadProgress, _ref1, _ref2, _ref3, _ref4, _ref5, _ref6, _ref7;
              downloadProgress = ((_ref1 = (_ref2 = r1.response) != null ? (_ref3 = _ref2.connection) != null ? _ref3.socket.bytesRead : void 0 : void 0) != null ? _ref1 : 0) / fileSize * 100;
              uploadProgress = ((_ref4 = (_ref5 = r2.req) != null ? (_ref6 = _ref5.connection) != null ? (_ref7 = _ref6.socket) != null ? _ref7._bytesDispatched : void 0 : void 0 : void 0) != null ? _ref4 : 0) / fileSize * 100;
              if (oldProgress.download === downloadProgress && oldProgress.upload === uploadProgress) {
                return;
              }
              oldProgress = {
                download: downloadProgress,
                upload: uploadProgress
              };
              Task.update({
                userId: socket.userId,
                path: taskPath
              }, {
                downloadProgress: downloadProgress,
                uploadProgress: uploadProgress
              }, function(err, count) {});
              io.sockets.clients().filter(function(x) {
                return x.userId === socket.userId;
              }).forEach(function(x) {
                return x.volatile.emit("progress", {
                  taskPath: taskPath,
                  download: downloadProgress,
                  upload: uploadProgress
                });
              });
              if (downloadProgress - uploadProgress > 25 * 1 << 20) {
                return r1.pause();
              } else if (downloadProgress - uploadProgress < 5 * 1 << 20) {
                return r1.resume();
              }
            }, 100);
          });
        });
        return r2.on("response", function(response) {
          Task.update({
            userId: socket.userId,
            path: taskPath
          }, {
            downloadProgress: 0,
            uploadProgress: 0
          }, function(err, count) {});
          io.sockets.clients().filter(function(x) {
            return x.userId === socket.userId;
          }).forEach(function(x) {
            return x.volatile.emit("progress", {
              taskPath: taskPath,
              download: 0,
              upload: 0
            });
          });
          return clearInterval(si);
        });
      }
    });
  });
  return socket.on("failureAck", function(_arg, callback) {
    var taskPath;
    taskPath = _arg.taskPath;
    if (socket.userId == null) {
      return callback({
        success: false
      });
    }
    return Task.update({
      userId: socket.userId,
      path: taskPath,
      status: "post_failure"
    }, {
      $unset: {
        status: ""
      }
    }, function(err, count) {
      if (count !== 1) {
        return {
          callback: false
        };
      }
      callback({
        success: true
      });
      return io.sockets.clients().filter(function(x) {
        return x !== socket && x.userId === socket.userId;
      }).forEach(function(x) {
        return x.emit("failureAck", {
          taskPath: taskPath
        });
      });
    });
  });
});

mongoose.connection.once("open", function() {
  console.log("Connected to MongoDB");
  return Task.update({
    status: {
      $in: ["posting", "transferring"]
    }
  }, {
    status: "post_failure",
    $unset: {
      downloadProgress: 0,
      uploadProgress: 0
    }
  }, {
    multi: true
  }, function(err, count) {
    var port, _ref;
    if (err != null) {
      console.log(err);
    }
    if (count > 0) {
      console.log("" + count + " tasks failed");
    }
    return server.listen((port = (_ref = process.env.PORT) != null ? _ref : 5080), function() {
      return console.log("Listening on port " + port);
    });
  });
});
