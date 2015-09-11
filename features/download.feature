Feature: Uploaded files can then be downloaded

 Scenario: Original filename is retained
  Given a file named "my-super-music.mp3" has been uploaded
  When I download the file
  Then the downloaded file is named "my-super-music.mp3"

 Scenario: Original content is retained
  Given a file has been uploaded
  When I download the file
  Then the downloaded file has the same content as the uploaded file

 Scenario: Original size is retained
  Given a file has been uploaded
  When I download the file
  Then the downloaded file has the same size as the uploaded file

 Scenario: Upload time is sent in Last-Modified header
  Given a file has been uploaded
  When I download the file
  Then the Last-Modified header is set to the upload time

 Scenario: URLs are friendly to mixing up look alike letters
  Given a file has been uploaded
  When I enter the link mixing up 'l' and '1'
  Then I should get the original file

 Scenario: Access to an non-existing file
  When I try to access a non-existing file
  Then I should get a 404 error

 Scenario: Access to an existing file with a bad decryption key
  Given a file has been uploaded
  When I enter the link with a bad decryption key
  Then I should get a 404 error
