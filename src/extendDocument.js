var _ = require('underscore');

module.exports = exports = function(mongraphOptions) {

  var Document            = mongraphOptions.mongoose.Document
    , Schema              = mongraphOptions.mongoose.Schema
    , graphabilityOptions = mongraphOptions.graphability
    , processtools        = mongraphOptions.processtools
    , neo4j               = mongraphOptions.neo4j
    , DocumentNode        = mongraphOptions.DocumentNode;

  Schema.prototype.enableGraphability = function() {
    this.set('graphability', _.extend({}, graphabilityOptions));
  }

  Schema.prototype.disableGraphability = function() {
    var graphability = this.get('graphability');
    if (graphability)
      graphabilityOptions = graphability;
    this.set('graphability', null);
  }

  Document.prototype._cachedNode_ = null; // will contain a cache node object

  Document.prototype.dataForNode = function() {
    var self = this
      , paths = self.schema.paths
      , values  = {};

    for (var path in paths) {
      var definition = paths[path];
      if (definition.options)
        if (definition.options.graph)
          values[path] = self.get(path);
    }
    return (Object.keys(values).length > 0) ? values : null;
  }

  Document.prototype.fieldsToIndexForNode = function() {
    var self    = this
      , paths   = self.schema.paths
      , fields  = [];

    fields.push('_id');
    for (var path in paths) {
      var definition = paths[path];
      if (definition.options)
        if (definition.options.index)
          fields.push(path);
    }
    return fields;
  }

  Document.prototype.indexForNode = function() {
    var fields = this.fieldsToIndexForNode()
      , result = {};
    for (var i=0; i < fields.length; i++) {
      var value = this.get(fields[i]);
      if (typeof value !== 'undefined')
        result[fields[i]] = this.get(fields[i]);
    }
    return result;
  }

  Document.prototype.getNode = function(options, cb) {
    if (typeof options === 'function') {
      cb = options;
      options = {};
    }

    if (!this.schema.get('graphability'))
      return cb(Error('No graphability enabled'), null, options);
    
    doc = this;

    // apply on default options
    options = _.extend({
      forceReload: false,          // you can force a reloading of a node so you can ensure to get the latest existing node directly from db
      doCreateIfNotExists: false,  // persist the node if no corresponding node exists
      forceCreation: false         // forces to create a node (this is needed because mongoose marks each document as)
    }, options);

    if ((mongraphOptions.cacheNodeInDocument) && (doc._cachedNode_) && (!options.forceReload))
      return cb(null, doc._cachedNode_, options);

    var collectionName = doc.constructor.collection.name;
    var id = processtools.getObjectIDAsString(doc);

    // # TODO: cache existing node
    
    var _processNode = function(err, node) {
      // store node_id on document
      if (mongraphOptions.cacheNodeInDocument)
        doc._cachedNode_ = node;
      
      // store document data also als in node -> untested and not recommend
      if (mongraphOptions.storeDocumentInGraphDatabase) {
        node.data = doc.toObject(mongraphOptions.storeDocumentInGraphDatabase);
        node.save(cb);
      } else {
        cb(null, node, options);
      }
    }

    if ((doc.isNew) && (!options.forceCreation)) {
      return cb(new Error("Can't get a node of an unpersisted document"), null, options);
    } else if ((options.doCreateIfNotExists) || (options.forceCreation)) {
      // create a new node
      var Node = DocumentNode.register_model(mongraphOptions.processtools.getModelNameByCollectionName(collectionName));
      node = new Node({
        _id: id,
        _collection: collectionName
      });
      // node.label = mongraphOptions.processtools.getModelNameByCollectionName(collectionName);
      node.save(_processNode);
    } else {
      DocumentNode.findOne({ _id: String(doc.id) }, _processNode);
    }
  }

  return Document;
}