Feature: Links to download files

 Scenario: Uploaders get an URL to give to downloaders
  When I upload a file
  Then I see an URL to give to downloaders

 Scenario: The original filename is kept secret
  When I upload a file
  Then the download URL does not contain the original filename
