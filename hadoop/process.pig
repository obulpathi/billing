-- NEEDS TO BE FIXED
-- ssl enabled: we can read only the secure.*.gz files and use secure for them and non-secure for everything else
-- cartesian join, instead of normal join

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

normal_logs = LOAD '$INPUT/altcdn_[0-9]*.gz' USING PigStorage('\t') AS (date, time, ip, method, uri, status, bytes:long, time_taken, referer, user_agent, cookie, country);

secure_logs = LOAD '$INPUT/altcdn_secure_[0-9]*.gz' USING PigStorage('\t') AS (date, time, ip, method, uri, status, bytes:long, time_taken, referer, user_agent, cookie, country);

-- load country to region map file

country_map = LOAD 'country_map.tsv' USING PigStorage('\t') AS (country, region);

-- join filtered_logs and country_map to add region to the logs using fragment-replicate join (on country_map)

normal_region_logs = JOIN normal_logs BY country, country_map BY country USING 'replicated';
secure_region_logs = JOIN secure_logs BY country, country_map BY country USING 'replicated';

-- filter the domain, bytes and region fields

normal_domain_logs = FOREACH normal_region_logs GENERATE REGEX_EXTRACT(uri, '/([^/]*).raxcdn.com(/.*)', 1) AS domain, bytes, region;
secure_domain_logs = FOREACH secure_region_logs GENERATE REGEX_EXTRACT(uri, '/([^/]*).raxcdn.com(/.*)', 1) AS domain, bytes, region;

-- load domain to project_id and service_id map file

domain_map = LOAD '$INPUT/domains_map.tsv' USING PigStorage('\t') AS (domain, project_id, service_id);

-- join domain_logs and domain_map by domain using replicated join (on domain_map)

normal_joined_logs = JOIN normal_domain_logs BY domain, domain_map BY domain USING 'replicated';
secure_joined_logs = JOIN secure_domain_logs BY domain, domain_map BY domain USING 'replicated';

-- group records by domain and region
normal_grouped_logs = GROUP normal_joined_logs BY (normal_domain_logs::domain, project_id, service_id, region);
secure_grouped_logs = GROUP secure_joined_logs BY (secure_domain_logs::domain, project_id, service_id, region);

-- FORMAT: eventType, eventID, tenantId, resourceId, resourceName, offerModel, sslEnabled, startTime, endTime, edgeLocation, bandwidthOut
-- aggregate bandwidth usage

normal_aggregated_bw = FOREACH normal_grouped_logs GENERATE 'bandwidthOut', utils.uuid(), group.project_id, group.service_id, group.normal_domain_logs::domain, 'CDN', 'false', '$STARTTIME', '$ENDTIME', group.region, SUM(normal_joined_logs.bytes);
secure_aggregated_bw = FOREACH secure_grouped_logs GENERATE 'bandwidthOut', utils.uuid(), group.project_id, group.service_id, group.secure_domain_logs::domain, 'CDN', 'true', '$STARTTIME', '$ENDTIME', group.region, SUM(secure_joined_logs.bytes);

-- FORMAT: eventType, eventID, tenantId, resourceId, resourceName, offerModel, sslEnabled, startTime, endTime, edgeLocation, requestCount
-- aggregate request count

normal_aggregated_count = FOREACH normal_grouped_logs GENERATE 'requestCount', utils.uuid(), group.project_id, group.service_id, group.normal_domain_logs::domain, 'CDN', 'false', '$STARTTIME', '$ENDTIME', group.region, COUNT(normal_joined_logs);
secure_aggregated_count = FOREACH secure_grouped_logs GENERATE 'requestCount', utils.uuid(), group.project_id, group.service_id, group.secure_domain_logs::domain, 'CDN', 'true', '$STARTTIME', '$ENDTIME', group.region, COUNT(secure_joined_logs);

-- join aggregated logs
aggregated_logs = UNION normal_aggregated_bw, normal_aggregated_count, secure_aggregated_bw, secure_aggregated_count;

-- SAVE aggregared logs
STORE aggregated_logs INTO '$OUTPUT' USING PigStorage('\t');
