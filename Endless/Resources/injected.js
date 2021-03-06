if (typeof __endless == "undefined") {
var __endless = {
	openedTabs: {},

	ipcTimeoutMS: 2000,

	ipc: function(url) {
		var iframe = document.createElement("iframe");
		iframe.setAttribute("src", "endlessipc://" + url);
		iframe.setAttribute("height", "1px");
		iframe.setAttribute("width", "1px");
		document.documentElement.appendChild(iframe);
		iframe.parentNode.removeChild(iframe);
		iframe = null;
	},

	ipcDone: null,
	ipcAndWaitForReply: function(url) {
		this.ipcDone = null;

		var start = (new Date()).getTime();
		this.ipc(url);

		while (this.ipcDone == null) {
			if ((new Date()).getTime() - start > this.ipcTimeoutMS) {
				console.log("took too long waiting for IPC reply");
				break;
			}
		}

		return;
	},

	randID: function() {
		function s4() {
			return Math.floor((1 + Math.random()) * 0x10000).toString(16)
				.substring(1);
		}
		return s4() + s4() + '-' + s4() + '-' + s4() + '-' + s4() + '-' +
			s4() + s4() + s4();
	},

	hookIntoBlankAs: function() {
		document.body.addEventListener("click", function() {
			if (event.target.tagName == "A" && event.target.target == "_blank") {
				if (event.type == "click") {
					event.preventDefault();
					if (window.open(event.target.href) == null)
						window.location = event.target.href;
					return false;
				}
				else {
					console.log("not opening _blank a from " + event.type +
						" event");
				}
			}
		}, false);
	},

	FakeLocation: function(real) {
		this.id = null;

		for (var prop in real) {
			this["_" + prop] = real[prop];
		}

		this.toString = function() {
			return this._href;
		};
	},

	FakeWindow: function(id) {
		this.id = id;
		this.opened = false;
		this._location = null;
		this._name = null;
	},
};

(function () {
	"use strict";

	__endless.FakeLocation.prototype = {
		constructor: __endless.FakeLocation,
	};

	[ "hash", "hostname", "href", "pathname", "port", "protocol", "search",
	"username", "password", "origin" ].forEach(function(property) {
		Object.defineProperty(__endless.FakeLocation.prototype, property, {
			set: function(v) {
				eval("this._" + property + " = null;");
				__endless.ipcAndWaitForReply("fakeWindow.setLocationParam/" +
					this.id + "/" + property + "?" + encodeURIComponent(v));
			},
			get: function() {
				eval("this._" + property + " = null;");
				__endless.ipcAndWaitForReply("fakeWindow.getLocationParam/" +
					this.id + "/" + property + "?" + encodeURIComponent(v));
			},
		});
	});

	__endless.FakeWindow.prototype = {
		constructor: __endless.FakeWindow,

		set location(loc) {
			this._location = new __endless.FakeLocation();
			__endless.ipcAndWaitForReply("fakeWindow.setLocation/" + this.id +
				"?" + encodeURIComponent(loc));
			this._location.id = this.id;
		},
		set name(n) {
			this._name = null;
			__endless.ipcAndWaitForReply("fakeWindow.setName/" + this.id + "?" +
				encodeURIComponent(n));
		},
		set opener(o) {
		},

		get location() {
			this._location = new __endless.FakeLocation();
			__endless.ipcAndWaitForReply("fakeWindow.getLocation/" + this.id);
			this._location.id = this.id;
			return this._location;
		},
		get name() {
			this._name = null;
			__endless.ipcAndWaitForReply("fakeWindow.getName/" + this.id);
			return this._name;
		},
		get opener() {
		},

		close: function() {
			__endless.ipcAndWaitForReply("fakeWindow.close/" + this.id);
		},
	};

	window.onerror = function(msg, url, line) {
		console.error("[on " + url + ":" + line + "] " + msg);
	}

	window.open = function (url, name, specs, replace) {
		var id = __endless.randID();

		__endless.openedTabs[id] = new __endless.FakeWindow(id);

		/* fake a mouse event clicking on a link, so that our webview sees the
		 * navigation type as a mouse event; this prevents popup spam since
		 * dispatchEvent() won't do anything if we're not in a mouse event
		 * already */
		var l = document.createElement("a");
		l.setAttribute("href", "endlessipc://window.open/" + id);
		l.setAttribute("target", "_blank");
		var e = document.createEvent("MouseEvents");
		e.initMouseEvent("click", true, true, window, 0, 0, 0, 0, 0, false,
			false, false, false, 0, null);
		l.dispatchEvent(e);

		__endless.ipcAndWaitForReply("noop");

		if (!__endless.openedTabs[id].opened) {
			console.error("window failed to open");
			/* TODO: send url to ipc anyway to show popup blocker notice */
			return null;
		}

		if (name !== undefined && name != '')
			__endless.openedTabs[id].name = name;
		if (url !== undefined && url != '')
			__endless.openedTabs[id].location = url;

		window.event.preventDefault();

		return __endless.openedTabs[id];
	};

	window.close = function () {
		__endless.ipcAndWaitForReply("window.close");
	};

	/* pipe back to app */
	console = {
		_log: function(urg, args) {
			if (args.length == 1)
				args = args[0];

			__endless.ipc("console.log/" + urg + "?" +
				encodeURIComponent(JSON.stringify(args)));
		},
	};
	console.log = function() { console._log("log", arguments); };
	console.debug = function() { console._log("debug", arguments); };
	console.info = function() { console._log("info", arguments); };
	console.warn = function() { console._log("warn", arguments); };
	console.error = function() { console._log("error", arguments); };

	if (document.readyState == "complete" || document.readyState == "interactive")
		__endless.hookIntoBlankAs();
	else
		document.addEventListener("DOMContentLoaded",
			__endless.hookIntoBlankAs, false);
}());
}
