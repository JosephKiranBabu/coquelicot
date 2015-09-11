Feature: Files storage protect users privacy

 Scenario: Files are stored encrypted
  When I upload a file
  Then the file is stored encrypted on the server

 # This is meant to make harder to match connection log with actual files
 Scenario: Files are stored under a different name the than the URL
  When I upload a file
  Then the file name on the server is different from the name in the URL
