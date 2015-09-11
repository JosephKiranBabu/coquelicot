Feature: Uploads can be limited to people owning an account on an IMAP server

 Background:
   Given the admin has configured the "imap" authentication method
   And the IMAP server knows "user@example.org" identified with "mailpass"

 Scenario: Uploads are denied without a login
   When I try to upload a file without a login
   Then I'm denied the upload

 Scenario: Uploads are denied with a wrong login
   Given I have entered "unknown@example.org" as IMAP login
   And I have entered "badpass" as IMAP password
   When I try to upload a file
   Then I'm denied the upload

 Scenario: Uploads are accepted with the right password
   Given I have entered "user@example.org" as IMAP login
   And I have entered "mailpass" as IMAP password
   When I try to upload a file
   Then the upload is accepted
