bunyan = require 'bunyan'
logger = bunyan.createLogger
	name : 'scgf_server'
@log = (args...)->
	logger.info.apply logger, args
@err = (args...)->
	logger.error.apply logger, args