Feature: Some restrictions exist on which files can be uploaded

 Scenario: Empty files are refused
  Given I have an empty file
  When I try to upload it
  Then the upload is refused as empty

 Scenario: Files bigger than the limit are refused
  Given the admin has set a maximum file size
  And I have a file bigger than the limit
  When I try to upload it
  Then the upload is refused as too big
