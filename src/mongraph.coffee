processtools = require('./processtools')
mongraphMongoosePlugin = require('./mongraphMongoosePlugin')

# shortcut
constructorNameOf = processtools.constructorNameOf

config = {}

init = (options) ->

  options = {} if typeof options isnt 'object'

  # set default options
  # TODO: extend default options
  config.options  = options
  config.mongoose = options.mongoose
  config.graphdb  = options.neo4j
  config.options.overwriteProtypeFunctions ?= true
  config.options.storeDocumentInGraphDatabase ?= false # TODO: implement
  config.options.cacheNodes ?= true # TODO: implement
  config.options.loadMongoDBRecords ?= true
  config.options.extendSchemaWithMongoosePlugin ?= true
  config.options.relationships ?= {}
  config.options.relationships.storeTimestamp = true # is always true
  config.options.relationships.storeIDsInRelationship = true # is always true as long it's mandatory for mongraph 
  config.options.relationships.bidirectional ?= false

  # TODO: work with one option object containing all references
  throw new Error("mongraph needs a mongoose reference as parameter") unless constructorNameOf(config.mongoose) is 'Mongoose'
  throw new Error("mongraph needs a neo4j graphdatabase reference as paramater") unless constructorNameOf(config.graphdb) is 'GraphDatabase'

  if config.options.overwriteProtypeFunctions isnt true
    # Check that we don't override existing functions
    # throw exception if so
    # Check Monogoose
    for functionName in [ "getRelationships", "createRelationshipTo", "deleteRelationshipTo", "getNode", "findEquivalentNode", "findOrCreateEquivalentNode", "getRelatedDocuments", "_graph" ]
      throw new Error("Will not override mongoose::Document.prototype.#{functionName}") unless typeof config.mongoose.Document::[functionName] is 'undefined'
    # Check Neo4j
    node = config.graphdb.createNode()
    for functionName in [ "getCollectionName", "getMongoId" ]
      throw new Error("Will not override neo4j::Node.prototype.#{functionName}") unless typeof node.constructor::[functionName] is 'undefined'

  # extend Document(s) with Node/GraphDB interoperability
  require('./extendDocument')(config.mongoose, config.graphdb, config.options)
  # extend Node(s) with DocumentDB interoperability
  require('./extendNode')(config.graphdb, config.mongoose, config.options)
  
  # TODO: currently we must init() mongraph before defining any schema
  # solution could be: Activate it in project manually before defining models... ?!
  
  # Load plugin and extend schemas with middleware
  # -> http://mongoosejs.com/docs/plugins.html
  config.mongoose.plugin(mongraphMongoosePlugin) if config.options.extendSchemaWithMongoosePlugin


module.exports = {init,config,processtools}

