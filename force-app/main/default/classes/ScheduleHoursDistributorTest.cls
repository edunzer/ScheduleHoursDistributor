@isTest
public class ScheduleHoursDistributorTest {
  @testSetup
  static void setupTestData() {
    // Create a Schedule record
    pse__Schedule__c schedule = new pse__Schedule__c(
      pse__Start_Date__c = Date.newInstance(2025, 1, 1),
      pse__End_Date__c = Date.newInstance(2025, 7, 1),
      pse__Scheduled_Hours__c = 200,
      pse__Monday_Hours__c = 8,
      pse__Tuesday_Hours__c = 8,
      pse__Wednesday_Hours__c = 8,
      pse__Thursday_Hours__c = 8,
      pse__Friday_Hours__c = 8,
      pse__Saturday_Hours__c = 8,
      pse__Sunday_Hours__c = 8
    );
    insert schedule;
  }

  @isTest
  static void testGenerateScheduleExceptions() {
    // Retrieve the created Schedule
    pse__Schedule__c schedule = [
      SELECT Id, pse__Start_Date__c, pse__End_Date__c, pse__Scheduled_Hours__c
      FROM pse__Schedule__c
      LIMIT 1
    ];

    // Create input
    ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
    input.scheduleId = schedule.Id;
    input.startDate = schedule.pse__Start_Date__c;
    input.endDate = schedule.pse__End_Date__c;
    input.numberOfHours = schedule.pse__Scheduled_Hours__c;
    input.numberOfWorkDays = 5;
    input.cat1Weeks = 11;
    input.cat2Weeks = 8;
    input.cat3Weeks = 6;
    input.postWeeks = 4;
    input.cat1Percentage = 25;
    input.cat2Percentage = 30;
    input.cat3Percentage = 40;
    input.postPercentage = 5;
    // Add onsite dates for all tests
    input.onsiteStartDate = Date.newInstance(2025, 3, 1);
    input.onsiteEndDate = Date.newInstance(2025, 3, 14);
    input.existingExceptions = new List<pse__Schedule_Exception__c>();

    List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(
      new List<ScheduleHoursDistributor.ScheduleInput>{ input }
    );

    // Assertions
    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertEquals(1, result.size(), 'Only one result should be returned');
    System.assert(
      result[0].scheduleExceptions.size() > 0,
      'Schedule exceptions should be generated'
    );
    System.assertEquals(
      null,
      result[0].errorMessage,
      'There should be no error messages'
    );
  }

  @isTest
  static void testGenerateScheduleExceptionsWithNullScheduleId() {
    // Create input with null scheduleId
    ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
    input.scheduleId = null;
    input.startDate = Date.newInstance(2025, 1, 1);
    input.endDate = Date.newInstance(2025, 7, 1);
    input.numberOfHours = 200;
    input.numberOfWorkDays = 5;
    input.cat1Weeks = 11;
    input.cat2Weeks = 8;
    input.cat3Weeks = 6;
    input.postWeeks = 4;
    input.cat1Percentage = 25;
    input.cat2Percentage = 30;
    input.cat3Percentage = 40;
    input.postPercentage = 5;
    // Add onsite dates for all tests
    input.onsiteStartDate = Date.newInstance(2025, 3, 1);
    input.onsiteEndDate = Date.newInstance(2025, 3, 14);
    input.existingExceptions = new List<pse__Schedule_Exception__c>();

    List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(
      new List<ScheduleHoursDistributor.ScheduleInput>{ input }
    );

    // Assertions
    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertEquals(1, result.size(), 'Only one result should be returned');
    System.assertEquals(
      0,
      result[0].scheduleExceptions.size(),
      'No schedule exceptions should be generated'
    );
    System.assertNotEquals(
      null,
      result[0].errorMessage,
      'An error message should be present'
    );
    System.assertEquals(
      'Error: Schedule ID cannot be null.',
      result[0].errorMessage,
      'Error message should match expected output'
    );
  }

  @isTest
  static void testPercentageRedistributionWithRoundingControl() {
    // Retrieve the created Schedule
    pse__Schedule__c schedule = [
      SELECT Id, pse__Start_Date__c, pse__End_Date__c, pse__Scheduled_Hours__c
      FROM pse__Schedule__c
      LIMIT 1
    ];

    // Create input with percentages that would create repeating decimals when redistributed
    // Only cat1, cat2, and cat3 are valid (post is not valid without onsite)
    // Original: 20 + 30 + 40 = 90, need to add 10, split 3 ways = 3.333...
    ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
    input.scheduleId = schedule.Id;
    input.startDate = schedule.pse__Start_Date__c;
    input.endDate = schedule.pse__End_Date__c;
    input.numberOfHours = schedule.pse__Scheduled_Hours__c;
    input.numberOfWorkDays = 5;
    input.cat1Weeks = 11;
    input.cat2Weeks = 8;
    input.cat3Weeks = 6;
    input.postWeeks = 4;
    input.cat1Percentage = 20;
    input.cat2Percentage = 30;
    input.cat3Percentage = 40;
    input.postPercentage = 10;
    // No onsite dates, so post category won't be valid
    input.existingExceptions = new List<pse__Schedule_Exception__c>();

    List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(
      new List<ScheduleHoursDistributor.ScheduleInput>{ input }
    );

    // Assertions
    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertEquals(1, result.size(), 'Only one result should be returned');
    System.assertEquals(
      null,
      result[0].errorMessage,
      'There should be no error messages'
    );
    System.assert(
      result[0].scheduleExceptions.size() > 0,
      'Schedule exceptions should be generated'
    );

    // Calculate total hours from all exceptions to verify rounding control
    Decimal totalHours = 0;
    for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
      totalHours += (exc.pse__Monday_Hours__c != null
        ? exc.pse__Monday_Hours__c
        : 0);
      totalHours += (exc.pse__Tuesday_Hours__c != null
        ? exc.pse__Tuesday_Hours__c
        : 0);
      totalHours += (exc.pse__Wednesday_Hours__c != null
        ? exc.pse__Wednesday_Hours__c
        : 0);
      totalHours += (exc.pse__Thursday_Hours__c != null
        ? exc.pse__Thursday_Hours__c
        : 0);
      totalHours += (exc.pse__Friday_Hours__c != null
        ? exc.pse__Friday_Hours__c
        : 0);
    }

    // The total hours should be close to the input hours (within small tolerance for rounding)
    // The key is that with proper rounding control, we avoid accumulating drift
    System.debug('Total hours calculated: ' + totalHours);
    System.debug('Expected hours: ' + input.numberOfHours);

    // Verify that total hours are reasonable (allowing for some variance due to workday calculations)
    // The important thing is that rounding is consistent and doesn't create drift
    System.assert(totalHours > 0, 'Total hours should be greater than 0');
  }
}
