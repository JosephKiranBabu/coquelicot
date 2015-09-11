Feature: Uploads can be limited to people having a shared password

 Background:
   Given the admin has configured the "simplepass" authentication method
   And the upload password is set to "uploadsecret"

 Scenario: Uploads are denied without a password
   When I try to upload a file without an upload password
   Then I'm denied the upload

 Scenario: Uploads are denied with a wrong password
   Given I have entered "wrong" as the upload password
   When I try to upload a file
   Then I'm denied the upload

 Scenario: Uploads are accepted with the right password
   Given I have entered "uploadsecret" as the upload password
   When I try to upload a file
   Then the upload is accepted
