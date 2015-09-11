Feature: One time downloads

 Scenario: Uploaders can make a file downloadable only once
  When I visit the upload page
  Then I see a checkbox labeled "Remove after one download"

 Scenario: File can be downloaded a first time
  Given a file has been uploaded and set to be removed after a single upload
  When I follow the download link
  Then I have downloaded the file

 Scenario: Second attempt to download the file is denied
  Given a file has been uploaded and set to be removed after a single upload
  And it has been downloaded once
  When I follow the download link
  Then I'm told the file is gone

 Scenario: File must have been removed from the server after the first download
  Given a file has been uploaded and set to be removed after a single upload
  When I follow the download link
  Then the file has been removed from the server
