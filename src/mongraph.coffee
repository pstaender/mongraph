processtools = require('./processtools')
mongraphMongoosePlugin = require('./mongraphMongoosePlugin')
_ = require('underscore')

# bare config 
config = { options: {} }
alreadyInitialized = false

init = (options) ->

  options = {} if typeof options isnt 'object'

  # set default options
  _.extend(config.options, options)
  config.mongoose = options.mongoose
  config.graphdb  = options.neo4j
  config.options.overrideProtypeFunctions ?= false
  config.options.storeDocumentInGraphDatabase = false # TODO: implement
  config.options.cacheNodes ?= true
  config.options.loadMongoDBRecords ?= true
  config.options.extendSchemaWithMongoosePlugin ?= true
  config.options.relationships ?= {}
  config.options.relationships.storeTimestamp ?= true
  config.options.relationships.storeIDsInRelationship = true # must be true as long it's needed for mongraph to work as expected 
  config.options.relationships.bidirectional ?= false
  config.options.relationships.storeInDocument ?= false # will produce redundant data (stored in relationships + document)
  config.options.cacheAttachedNodes ?= true # recommend to decrease requests to neo4j

  # Allow overriding if mongrapg already was inizialized
  config.options.overrideProtoypeFunctions = true if alreadyInitialized
  
  # used for extendDocument + extendNode
  config.options.mongoose = options.mongoose
  config.options.graphdb  = options.neo4j

  throw new Error("mongraph needs a mongoose reference as parameter") unless processtools.constructorNameOf(config.mongoose) is 'Mongoose'
  throw new Error("mongraph needs a neo4j graphdatabase reference as paramater") unless processtools.constructorNameOf(config.graphdb) is 'GraphDatabase'

  # extend Document(s) with Node/GraphDB interoperability
  require('./extendDocument')(config.options)
  # extend Node(s) with DocumentDB interoperability
  require('./extendNode')(config.options)

  # Load plugin and extend schemas with middleware
  # -> http://mongoosejs.com/docs/plugins.html
  config.mongoose.plugin(mongraphMongoosePlugin, config.options) if config.options.extendSchemaWithMongoosePlugin

  alreadyInitialized = true


module.exports = {init,config,processtools}

