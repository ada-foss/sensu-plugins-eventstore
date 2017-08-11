#Change Log
This CHANGELOG follows the format listed at [Keep A Changelog](http://keepachangelog.com/)

## [0.0.27] - 2017-08-11
### Added
- --eventstore\_identifier argument for metrics-eventstore-stats-stream.rb so that more than one eventstore instance from one box can be monitored
### Fixed
- same treatment for discover\_via\_dns option in metrics-eventstore-stats-stream.rb as in 0.0.26, meaning the option is meaningful now

## [0.0.26] - 2017-08-08
### Added
- check-projections.rb, checks API endpoint and projections/any to confirm that all projections are running and at a specifiable level of progress
- check for epoch position in check-gossip.rb, confirms that target server is not lagging too far behind master and can be configured with a threshold
### Fixed
- inverts logic of discover\_via\_dns option, so that it can be switched on as a switch from the command line, as this didn't seem to be configurable to false from the command line
- fix for expected\_nodes option, which was being passed in as a string and ignored previously, it is now respected when no\_discover\_via\_dns is set

## 0.0.1 - 2016-02-12
### Added
- initial release
