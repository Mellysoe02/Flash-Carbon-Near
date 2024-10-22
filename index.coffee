express = require 'express'
fs      = require 'fs'
url     = require 'url'
exif    = require 'exif-parser'
debug   = require('debug') 'flash-near'

sdcard  = __dirname + '/' + 'sdcard'

app = express()
app.disable 'x-powered-by'
app.disable 'etag'

watcher =
	changed: false
	isWatching: false
	watch: (dir) ->
		@FSWatcher.close() if @FSWatcher
		@FSWatcher = fs.watch dir, { presistent: true, recursive: true }, (event, filename) =>
			@changed = true
		@isWatching = true
	clear: -> @changed = false

command =
	100: (req, res, next) ->
		dir = req.query.DIR
		debug 'filelist  : %s', dir
		dir = "" if dir == "/"
		fs.readdir sdcard + '/' + dir, (err, files) ->
			items = files
				.filter (file) ->
					file.lastIndexOf '.', 0 isnt 0
				.map (file) ->
					stats = fs.statSync sdcard + '/' + dir + file
					attribute = if stats.isDirectory() then 1 << 4 else 0
					datetime = stats.ctime
					date =
						(datetime.getFullYear() - 1980) << 9 ||
						(datetime.getMonth() + 1) << 5 ||
						(datetime.getDate()) << 0
					time =
						(datetime.getHours()) << 11 ||
						(datetime.getMinutes()) << 5 ||
						(datetime.getSeconds() / 2) << 0
					"#{dir},#{file},#{stats.size},#{attribute},#{date},#{time}"
			items.unshift 'WLANSD_FILELIST'
			res.send items.join('\n')
			next()
	101: (req, res, next) ->
		dir = req.query.DIR
		debug 'filecount : %s', dir
		fs.readdir sdcard + '/' + dir, (err, files) ->
			res.send (files.length - 2) + ''  # exclude '.' and '..'
			next()
	102: (req, res, next) ->
		watcher.watch sdcard if not watcher.isWatching
		res.send if watcher.changed then '1' else '0'
		watcher.clear()
		next()
	108: (req, res, next) ->
		res.send 'FLASHNEAR.0.0.1'
		next()

app.get '/command.cgi', (req, res, next) ->
	debug 'dispatching command %s', req.query.op
	command[req.query.op] req, res, next

app.get '/thumbnail.cgi', (req, res, next) ->
	file = decodeURIComponent url.parse(req.originalUrl, false).query
	debug 'thumbnail %s', file
	fs.readFile sdcard + file, (err, data) ->
		throw err if err
		result = exif.create(data).parse()
		debug 'exif %s', result
		if result.hasThumbnail()
			res.set 'Content-Type', 'image/jpg'
			res.set 'Content-Length', result.getThumbnailSize()
			res.send result.getThumbnailBuffer()
		else
			res.send 404
		next()

options =
	etag: false
	index: false
	lastModified: false
app.use '/', express.static sdcard, options


port = process.env.PORT or 3000
server = app.listen port, ->
	console.log server.address().address
	console.log server.address().port
