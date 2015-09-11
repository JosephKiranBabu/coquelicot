Feature: Uploaders can choose how long files will stay on the server

 Scenario: Uploaders can select different limits
  When I visit the upload page
  Then I see a field to select how long the file will stay on the server

 Scenario: Download is possible before the time limit
  Given a file has been uploaded
  When I follow the download link
  Then I have downloaded the file

 Scenario: Download is impossible after the time limit
  Given a file has been uploaded that will expire the next day
  When I follow the download link two days later
  Then I'm told the file is gone

 Scenario: No special errors visible a while after the limit has been reached
  Given a file has been uploaded that will expire the next day
  When I follow the download link a month later
  Then I'm told the file does not exist

 Scenario: Expired files are cleaned up
  Given a file has been uploaded that will expire the next day
  When two days have past
  Then the file has been removed from the server
