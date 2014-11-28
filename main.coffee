require	'coffee-script'
Loader		= require 'scgf'
Model 		= Loader.Model
Commands 	= Loader.Commands
Parse 		= require 'minimist'
fs			= require 'fs'
rl 			= require 'readline'
logger		= require './server/logger'

args = Parse process.argv.slice(2)

gameName = args.game
gamePath = './games/' + gameName
gameModule = gamePath + '/' + gameName + '.coffee'

input = args.input
if input
	input_path = './games/' + gameName + '/' + input
	rd = rl.createInterface
	    input: fs.createReadStream(input_path),
	    output: process.stdout,
	    terminal: false

fs.exists gameModule, (exists)->
	if !exists
		logger.log 'hey it\'s not there!'
		process.exit()

	module = require gameModule
	game = new Model.Game(gameName, module)

	process.stdin.on 'data', (chunk) ->
		chunk = chunk + ''
		lines = chunk.split('\n')
		for line in lines
			args = Parse line.split(' ')
			Commands.handle(game, args)

	if rd then rd.on 'line', (line)->
		logger.log '>' + line
		args = Parse line.split(' ')
		Commands.handle(game, args)