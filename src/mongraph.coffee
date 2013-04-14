processtools = require('./processtools')
mongraphMongoosePlugin = require('./mongraphMongoosePlugin')
_ = require('underscore')

# shortcut
constructorNameOf = processtools.constructorNameOf

# bare config 
config =
  options:
    collectionToModel: {}

init = (options) ->

  options = {} if typeof options isnt 'object'

  # set default options
  _.extend(config.options, options)
  config.mongoose = options.mongoose
  config.graphdb  = options.neo4j
  config.options.overwriteProtypeFunctions ?= false
  config.options.storeDocumentInGraphDatabase ?= false # TODO: implement
  config.options.cacheNodes ?= true # TODO: implement
  config.options.loadMongoDBRecords ?= true
  config.options.extendSchemaWithMongoosePlugin ?= true
  config.options.relationships ?= {}
  config.options.relationships.storeTimestamp = true # is always true
  config.options.relationships.storeIDsInRelationship = true # is always true as long it's mandatory for mongraph 
  config.options.relationships.bidirectional ?= false

  throw new Error("mongraph needs a mongoose reference as parameter") unless constructorNameOf(config.mongoose) is 'Mongoose'
  throw new Error("mongraph needs a neo4j graphdatabase reference as paramater") unless constructorNameOf(config.graphdb) is 'GraphDatabase'

  # extend Document(s) with Node/GraphDB interoperability
  require('./extendDocument')(config.mongoose, config.graphdb, config.options)
  # extend Node(s) with DocumentDB interoperability
  require('./extendNode')(config.graphdb, config.mongoose, config.options)
  # TODO: implement extendRelationship, extendPath

  # Load plugin and extend schemas with middleware
  # -> http://mongoosejs.com/docs/plugins.html
  config.mongoose.plugin(mongraphMongoosePlugin) if config.options.extendSchemaWithMongoosePlugin


module.exports = {init,config,processtools}

