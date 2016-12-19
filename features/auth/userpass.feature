Feature: Uploads can be limited to accounts registred in a configuration file

 Background:
   Given the admin has configured the "userpass" authentication method
   And the config file describes an account "user" identified with "secret"

 Scenario: Uploads are denied without a login
   When I try to upload a file without a login
   Then I'm denied the upload

 Scenario: Uploads are denied with a wrong login
   Given I have entered "unknown" as user login
   And I have entered "secret" as user password
   When I try to upload a file
   Then I'm denied the upload

 Scenario: Uploads are accepted with the right password
   Given I have entered "user" as user login
   And I have entered "secret" as user password
   When I try to upload a file
   Then the upload is accepted
