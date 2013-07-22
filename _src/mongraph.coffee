processtools = require('./processtools')
mongraphMongoosePlugin = require('./mongraphMongoosePlugin')
_ = require('underscore')
neo4jmapper = require('neo4jmapper')

# bare config 
config = { options: {} }
alreadyInitialized = false

init = (options) ->

  options = {} if typeof options isnt 'object'

  # set default options
  _.extend(config.options, options)
  config.mongoose = options.mongoose
  config.neo4j    = neo4jmapper(options.neo4j)
  config.options.overrideProtypeFunctions ?= false
  config.options.storeDocumentInGraphDatabase = false # TODO: implement
  config.options.loadMongoDBRecords ?= true
  config.options.extendSchemaWithMongoosePlugin ?= true
  config.options.relationships ?= {}
  config.options.relationships.storeTimestamp ?= true
  config.options.relationships.storeIDsInRelationship = true # must be true as long it's needed for mongraph to work as expected 
  config.options.relationships.bidirectional ?= false
  config.options.relationships.storeInDocument ?= false # will produce redundant data (stored in relationships + document)

  # Allow overriding if mongrapg already was inizialized
  config.options.overrideProtoypeFunctions = true if alreadyInitialized
  
  # used for extendDocument + extendNode
  config.options.mongoose = options.mongoose
  config.options.neo4j  = config.neo4j

  throw new Error("mongraph needs a mongoose reference as parameter") unless processtools.constructorNameOf(config.mongoose) is 'Mongoose'

  # extend Document(s) with Node/GraphDB interoperability
  require('./extendDocument')(config.options)
  # extend Node(s) with DocumentDB interoperability
  # require('./extendNode')(config.options)

  # Load plugin and extend schemas with middleware
  # -> http://mongoosejs.com/docs/plugins.html

  config.mongoose.plugin(mongraphMongoosePlugin, config.options) if config.options.extendSchemaWithMongoosePlugin

  alreadyInitialized = true

  { init, config, processtools }


module.exports = {init,config,processtools}

