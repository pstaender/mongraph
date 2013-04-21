_ = require('underscore')
processtools = require('./processtools')

# ## Helper as workaround for missing prototyp availibility of neo4j module Relationship object 
# TODO: implement load Documents/Nodes from processtools

# extends neo4j::Relationship
Relationship =

  toObject: ->
    { from: @from || null, to: @to || null, data: @_data?.data, id: @id, getParent: -> @  }

exports.extend = (relationshipObject) ->

  # TODO: maybe it would better to check constructor for 'Relationship' ?! 
  return relationshipObject unless typeof relationshipObject is 'object'

  _.extend(relationshipObject, Relationship)
  
