var mongraphMongoosePlugin = require('./mongraphMongoosePlugin')
  , _ = require('underscore')
  , neo4jmapper = require('neo4jmapper');

var alreadyInitialized = false
  , options = {};

module.exports = exports = {

  init: function(mongraphOptions) {

    if (!alreadyInitialized) {
      if ((typeof mongraphOptions !== 'object') || (!options))
        throw Error('You need to pass an json-object as 1st argument with { mongoose: …, neo4j: … }');
      if (typeof mongraphOptions.mongoose !== 'object')
        throw Error('You have to set a mongoose handler on { mongoose: … }');
      if (!mongraphOptions.neo4j)
        throw Error('You have to set a neo4j(url) on { neo4j: … }');
    }

    if (mongraphOptions) {
      options = _.extend({
        graphability: {
          middleware: {
            preRemove: true,
            preSave: true,
            postInit: true
          },
        },
        cacheNodeInDocument: true,
        storeDocumentInGraphDatabase: false,
        extendSchemaWithMongoosePlugin: true,
        storeDocumentInGraphDatabase: false, // not recommend to use
        relationships: {
          storeTimestamp: true,
          storeIDsInRelationship: true
        },
        neo4j: null,
        processtools: null
      }, options, mongraphOptions);
      options.neo4j = neo4jmapper(options.neo4j || options.neo4jurl);
    }

    options.processtools = require('./processtools').init(options.mongoose);

    // extend Document(s) with Node/GraphDB interoperability
    var Document = require('./extendDocument')(options).Document;
    // extend Node(s) with DocumentDB interoperability
    var DocumentNode = require('./extendNode')(options).DocumentNode;

    // Load plugin and extend schemas with middleware
    // -> http://mongoosejs.com/docs/plugins.html

    if (options.extendSchemaWithMongoosePlugin)
      options.mongoose.plugin(mongraphMongoosePlugin, options);

    alreadyInitialized = true;

    return {
      options: options,
      DocumentNode: DocumentNode
    };

  }

}