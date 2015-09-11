Feature: Coquelicot is available in multiple languages

Scenario: see available languages
 When I visit the main page
 Then I should see a link to the French version

Scenario: request a specific language
 Given I am on the main page
 When I follow the link to the French version
 Then the page should be in French
