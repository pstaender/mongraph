installneo4j:
	rm -rf neo4jserver
	mkdir neo4jserver
	cd neo4jserver && wget http://dist.neo4j.org/neo4j-community-2.0.0-M04-unix.tar.gz
	cd neo4jserver && tar -zxvf neo4j-community-2.0.0-M04-unix.tar.gz
	sed -i 's/HEADLESS=false/HEADLESS=true/g' ./neo4jserver/neo4j-community-2.0.0-M04/bin/neo4j
	./neo4jserver/neo4j-community-2.0.0-M04/bin/neo4j -u neo4j install
	service neo4j-service start
	sleep 3
