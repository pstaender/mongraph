processtools = require('./processtools')
mongraphMongoosePlugin = require('./mongraphMongoosePlugin')
_ = require('underscore')

# shortcut
constructorNameOf = processtools.constructorNameOf

# bare config 
config =
  options:
    collectionToModel: {}

# Register models
registerModels = (mongoose) ->
  if constructorNameOf(mongoose) is 'Mongoose'
    models = mongoose.models
  else unless mongoose
    throw new Error('Expecting a mongoose- or a mongoose.models-object for registration')
  else
    # we assume that we have mongoose.models here
    models = mongoose
  for modelName of models
    # add collectionName for each model
    {collection,modelName} = models[modelName]
    # register with collection and model name (easier to find and avoiding Person -> people problem)
    config.options.collectionToModel[collection.name] = modelName
  config.options.collectionToModel

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


module.exports = {init,config,processtools,registerModels}

