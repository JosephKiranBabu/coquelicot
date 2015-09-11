Feature: Uploads can be limited to people owning an account on a LDAP server

 Background:
   Given the admin has configured the "ldap" authentication method
   And the LDAP server knows "user" identified with "ldappass"

 Scenario: Uploads are denied without a login
   When I try to upload a file without a login
   Then I'm denied the upload

 Scenario: Uploads are denied with a wrong login
   Given I have entered "unknown" as LDAP login
   And I have entered "badpass" as LDAP password
   When I try to upload a file
   Then I'm denied the upload

 Scenario: Uploads are accepted with the right password
   Given I have entered "user" as LDAP login
   And I have entered "ldappass" as LDAP password
   When I try to upload a file
   Then the upload is accepted
