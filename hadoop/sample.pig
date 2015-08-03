-- Register libraries
REGISTER /usr/lib/pig/piggybank.jar;
REGISTER 'pigudfs.py' using jython as utils;

-- Shortcut definitions
DEFINE LogLoader org.apache.pig.piggybank.storage.apachelog.CombinedLogLoader();
DEFINE DayExtractor org.apache.pig.piggybank.evaluation.util.apachelogparser.DateExtractor('yyyy-MM-dd');
DEFINE HostExtractor org.apache.pig.piggybank.evaluation.util.apachelogparser.HostExtractor();

-- Apache Extended Log Format
-- date         time        ip          method  uri             status    bytes time_taken referer                                                                                              user_agent                                                                                                      cookie      Country
-- 2015-01-31	00:01:34	92.63.87.3	GET     /wp.altcdn.com/	301	      399	0	       "http://alea-laconica.gr/wp-admin/admin-ajax.php?action=kbslider_show_image&img=../wp-config.php"	"Mozilla/5.0 (Windows NT 6.2; WOW64) AppleWebKit/535.11 (KHTML, like Gecko) Chrome/17.0.963.65 Safari/535.11"	"-"         "US"
-- load the data
logs = LOAD 'sample.log' USING PigStorage('\t') AS (date, time, ip, method, uri, status, bytes:long, time_taken, referer, user_agent, cookie, country);

-- filter out the bad data
-- filtered_logs = FILTER logs BY bytes != '-';

-- load country to region map file
country_map = LOAD 'country_map.tsv' USING PigStorage('\t') AS (country, region);

-- join filtered_logs and country_map to add region to the logs using fragment-replicate join (on country_map)
region_logs = JOIN logs BY country, country_map BY country USING 'replicated';

-- filter the domain, bytes and region fields
domain_logs = FOREACH region_logs GENERATE REGEX_EXTRACT(uri, '/([^/]*)(.raxcdn.com)?(/.*)', 1) AS domain, bytes, region;

-- load domain to project_id and service_id map file
domain_map = LOAD 'sample.map' USING PigStorage('\t') AS (domain, project_id, service_id);

-- join domain_logs and domain_map by domain using replicated join (on domain_map)
joined_logs = JOIN domain_logs BY domain, domain_map BY domain USING 'replicated';

-- group records by domain and region
grouped_logs = GROUP joined_logs BY (domain_logs::domain, project_id, service_id, region);

-- FORMAT: eventType, eventID, tenantId, resourceId, resourceName, offerModel, sslEnabled, startTime, endTime, edgeLocation, bandwidthOut
-- aggregate bandwidth usage
aggregated_bw = FOREACH grouped_logs GENERATE 'bandwidth', utils.uuid(), group.project_id, group.service_id, group.domain_logs::domain, 'CDN', 'true', '2012-06-19T10:19:52Z', '2012-06-20T10:19:52Z', group.region, SUM(joined_logs.bytes);

-- FORMAT: eventType, eventID, tenantId, resourceId, resourceName, offerModel, sslEnabled, startTime, endTime, edgeLocation, requestCount
-- aggregate request count
aggregated_count = FOREACH grouped_logs GENERATE 'requestcount', utils.uuid(), group.project_id, group.service_id, group.domain_logs::domain, 'CDN', 'true', '2012-06-19T10:19:52Z', '2012-06-20T10:19:52Z', group.region, COUNT(joined_logs);

-- join aggregated logs
aggregated_logs = UNION aggregated_bw, aggregated_count;

-- DUMP sum_bytes;
STORE aggregated_logs INTO 'processed' USING PigStorage('\t');
