processtools = require('./processtools')

module.exports = exports = mongraphMongoosePlugin = (schema, options = {}) ->

  options.relationships ?= {}
  options.relationships.removeAllOutgoing  ?= true
  options.relationships.removeAllIncoming  ?= true
  options.relationships.storeInDocument    ?= false

  # node id of corresponding node
  schema.add
    _node_id: Number
    schema.add _relationships: {} # add an empty object as placeholder for relationships, use is optional

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
    next()
    # if option store relationships in document is activated
    if options.relationships.storeInDocument
      # Schema
      # 
      # typeOfRelationship: [
      #   from:
      #     collection: String
      #     _id: ObjectId
      #     data: {}
      #   to:
      #     collection: String
      #     _id: ObjectId
      #     data: {}
      # ]
      doc.getNode { forceCreation: true }, (err, node) ->
        doc.allRelationships '*', (err, relationships) ->
          if relationships?.length > 0
            # add relationships to object, sorted by type (see above for schema)
            sortedRelationships = {}
            for relation in relationships
              if relation._data?.type
                data = {}
                for part in [ 'from', 'to' ]
                  {collectionName,_id} = processtools.extractCollectionAndId(relation.data["_#{part}"])
                  data[part] =
                    collection: collectionName
                    _id: processtools.ObjectId(_id)
                sortedRelationships[relation._data.type] ?= []
                sortedRelationships[relation._data.type].push(data)
          doc._relationships = sortedRelationships
          done(err,null)
    else
      doc.getNode { forceCreation: true }, done
      

  


