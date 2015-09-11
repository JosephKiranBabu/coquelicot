Feature: Uploaders can set a password required to download the files

 Scenario: Decryption key is not in the URL if a download password has been set
  When I upload a file with "secret" as the download password
  Then the download URL does not contain the decryption key

 Scenario: A form allows on to enter the download password
  Given a file has been uploaded with a download password
  When I follow the download link
  Then I see a form to enter the download password

 Scenario: Download is denied with a bad password
  Given a file has been uploaded with "downloadpass" as the download password
  When I follow the download link
  And I enter "wrong" as the download password
  Then I'm told the password is wrong

 Scenario: File is available with the correct password
  Given a file has been uploaded with "downloadpass" as the download password
  When I follow the download link
  And I enter "downloadpass" as the download password
  Then I have downloaded the file
