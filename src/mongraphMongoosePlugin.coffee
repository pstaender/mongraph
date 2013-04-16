module.exports = exports = mongraphMongoosePlugin = (schema, options = {}) ->

  options.relationships ?= {}
  options.relationships.removeAllOutgoing  ?= true
  options.relationships.removeAllIncoming  ?= true
  options.relationships.storeInDocument    ?= false

  # node id of corresponding node
  schema.add _node_id: Number

  if options.relationships.storeInDocument
    # add an empty object as placeholder for relations
    # schema:
    # {
    #   likes: [ {
    #     from: {
    #       collection: String,
    #       _id: ObjectId,
    #     },
    #     to: {
    #       collection: String,
    #       _id: ObjectId,
    #     }
    #   } ]
    # }
    schema.add relationships: {}

  # Extend middleware for graph use

  # Remove also all relationships
  # TODO: maybe better/best practice not to do and leave nodes?!? 
  schema.pre 'remove', (errHandler, cb) ->
    opts =
      includeRelationships: options.relationships.removeAllOutgoing and options.relationships.removeAllOutgoing
    @removeNode opts, cb

  schema.pre 'save', true, (next, done) ->
    # Attach node
    doc = @
    # if options.relationships.storeInDocument
    next()
    doc.getNode { forceCreation: true }, done
      

  


