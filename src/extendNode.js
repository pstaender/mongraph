var _ = require('underscore');

module.exports = exports = function(mongraphOptions, cb) {

  var neo4j        = mongraphOptions.neo4j
    , Node         = mongraphOptions.neo4j.Node
    , mongoose     = mongraphOptions.mongoose
    , DocumentNode = null;

  DocumentNode = Node.register_model('Document', {
    indexes: {
      _collection: true
    },
    unique: {
      _id: true
    },
    getDocument: function(cb){
      if ((this.data._id) && (this.data._collection)) {

      } else {
        cb(Error("No _id or _collection found on this node"), null);
      }
    },
  },
  function(err, Document) {
    if (typeof cb === 'function')
      cb(err, Document);
  });

  return { DocumentNode: DocumentNode };
}