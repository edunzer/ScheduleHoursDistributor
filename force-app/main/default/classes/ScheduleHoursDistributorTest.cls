@isTest
public class ScheduleHoursDistributorTest {
    @testSetup
    static void setupTestData() {
        // Create two Schedule records: one that will have exceptions and one that will not
        pse__Schedule__c scheduleWithExceptions = new pse__Schedule__c(
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
        pse__Schedule__c scheduleNoExceptions = new pse__Schedule__c(
            pse__Start_Date__c = Date.newInstance(2026, 1, 1),
            pse__End_Date__c = Date.newInstance(2026, 7, 1),
            pse__Scheduled_Hours__c = 100,
            pse__Monday_Hours__c = 8,
            pse__Tuesday_Hours__c = 8,
            pse__Wednesday_Hours__c = 8,
            pse__Thursday_Hours__c = 8,
            pse__Friday_Hours__c = 8,
            pse__Saturday_Hours__c = 0,
            pse__Sunday_Hours__c = 0
        );
        insert new List<pse__Schedule__c>{ scheduleWithExceptions, scheduleNoExceptions };
        
        // Create some reusable schedule exceptions to be used by tests
        List<pse__Schedule_Exception__c> excs = new List<pse__Schedule_Exception__c>();
        // single-day holiday (zero hours) - explicitly set end date to same day to avoid overlap validation
        excs.add(new pse__Schedule_Exception__c(
            pse__Schedule__c = scheduleWithExceptions.Id,
            pse__Date__c = Date.newInstance(2025, 1, 8),
            pse__End_Date__c = Date.newInstance(2025, 1, 8),
            pse__Monday_Hours__c = 0, pse__Tuesday_Hours__c = 0, pse__Wednesday_Hours__c = 0, pse__Thursday_Hours__c = 0, pse__Friday_Hours__c = 0, pse__Saturday_Hours__c = 0, pse__Sunday_Hours__c = 0
        ));
        // multi-day holiday range (zero hours)
        excs.add(new pse__Schedule_Exception__c(
            pse__Schedule__c = scheduleWithExceptions.Id,
            pse__Date__c = Date.newInstance(2025, 3, 10),
            pse__End_Date__c = Date.newInstance(2025, 3, 12),
            pse__Monday_Hours__c = 0, pse__Tuesday_Hours__c = 0, pse__Wednesday_Hours__c = 0, pse__Thursday_Hours__c = 0, pse__Friday_Hours__c = 0, pse__Saturday_Hours__c = 0, pse__Sunday_Hours__c = 0
        ));
        // another single-day used in some scenarios (moved to avoid overlap with multi-day holiday)
        excs.add(new pse__Schedule_Exception__c(
            pse__Schedule__c = scheduleWithExceptions.Id,
            pse__Date__c = Date.newInstance(2025, 3, 13),
            pse__End_Date__c = Date.newInstance(2025, 3, 13),
            pse__Monday_Hours__c = 0, pse__Tuesday_Hours__c = 0, pse__Wednesday_Hours__c = 0, pse__Thursday_Hours__c = 0, pse__Friday_Hours__c = 0, pse__Saturday_Hours__c = 0, pse__Sunday_Hours__c = 0
        ));
        insert excs;
    }

    @isTest
    static void testGenerateScheduleExceptions() {
        // Retrieve the schedule that has the test exceptions
        pse__Schedule__c schedule = [SELECT Id, pse__Start_Date__c, pse__End_Date__c, pse__Scheduled_Hours__c FROM pse__Schedule__c WHERE pse__Start_Date__c = :Date.newInstance(2025,1,1) LIMIT 1];
        
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

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});

        // Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Only one result should be returned');
        System.assert(result[0].scheduleExceptions.size() > 0, 'Schedule exceptions should be generated');
        System.assertEquals(null, result[0].errorMessage, 'There should be no error messages');
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

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});

        // Assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Only one result should be returned');
        System.assertEquals(0, result[0].scheduleExceptions.size(), 'No schedule exceptions should be generated');
        System.assertNotEquals(null, result[0].errorMessage, 'An error message should be present');
        System.assertEquals('Error: Schedule ID cannot be null.', result[0].errorMessage, 'Error message should match expected output');
    }

    @isTest
    static void testStartDateAfterEndDateValidation() {
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c WHERE pse__Start_Date__c = :Date.newInstance(2025,1,1) LIMIT 1];
        input.scheduleId = schedule.Id;
        input.startDate = Date.newInstance(2025, 7, 2);
        input.endDate = Date.newInstance(2025, 7, 1);
        input.numberOfHours = 100;
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 1;
        input.cat2Weeks = 1;
        input.cat3Weeks = 1;
        input.postWeeks = 1;
        input.cat1Percentage = 25;
        input.cat2Percentage = 25;
        input.cat3Percentage = 25;
        input.postPercentage = 25;
        input.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});
        System.assertEquals(1, result.size());
        System.assertNotEquals(null, result[0].errorMessage);
        System.assertEquals('Error: Start Date must be on or before End Date.', result[0].errorMessage);
    }

    @isTest
    static void testOnsiteStartAfterEndDateValidation() {
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c WHERE pse__Start_Date__c = :Date.newInstance(2025,1,1) LIMIT 1];
        input.scheduleId = schedule.Id;
        input.startDate = Date.newInstance(2025, 1, 1);
        input.endDate = Date.newInstance(2025, 7, 1);
        input.numberOfHours = 100;
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 1;
        input.cat2Weeks = 1;
        input.cat3Weeks = 1;
        input.postWeeks = 1;
        input.cat1Percentage = 25;
        input.cat2Percentage = 25;
        input.cat3Percentage = 25;
        input.postPercentage = 25;
        input.onsiteStartDate = Date.newInstance(2025, 4, 10);
        input.onsiteEndDate = Date.newInstance(2025, 4, 5);
        input.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});
        System.assertEquals(1, result.size());
        System.assertNotEquals(null, result[0].errorMessage);
        System.assertEquals('Error: Onsite Start Date must be on or before Onsite End Date.', result[0].errorMessage);
    }

    @isTest
    static void testExistingMultiDayExceptionExcludesHolidayDates() {
        // Use the multi-day holiday inserted in @testSetup
        pse__Schedule_Exception__c holiday = [
            SELECT Id, pse__Date__c, pse__End_Date__c
            FROM pse__Schedule_Exception__c
            WHERE pse__End_Date__c != null
            LIMIT 1
        ];

        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c WHERE pse__Start_Date__c = :Date.newInstance(2025,1,1) LIMIT 1];
        input.scheduleId = schedule.Id;
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
        input.onsiteStartDate = Date.newInstance(2025, 3, 1);
        input.onsiteEndDate = Date.newInstance(2025, 3, 14);
        input.existingExceptions = new List<pse__Schedule_Exception__c>{ holiday };

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage);

        Date holStart = holiday.pse__Date__c;
        Date holEnd = holiday.pse__End_Date__c;

        // Ensure no generated exception overlaps the holiday range
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            Date s = exc.pse__Date__c;
            Date e = exc.pse__End_Date__c == null ? s : exc.pse__End_Date__c;
            Boolean overlaps = (s <= holEnd && e >= holStart);
            System.assertEquals(false, overlaps, 'Generated exception should not overlap holiday range: ' + s + ' - ' + e);
        }
    }

    @isTest
    static void testOnsiteGapWeekIsSevenDaysZeroHours() {
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c WHERE pse__Start_Date__c = :Date.newInstance(2025,1,1) LIMIT 1];
        input.scheduleId = schedule.Id;
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
        // Choose an onsite start mid-week to exercise week-start calculation
        input.onsiteStartDate = Date.newInstance(2025, 3, 5);
        input.onsiteEndDate = Date.newInstance(2025, 3, 10);
        input.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage);

        Boolean foundWeekGap = false;
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            if (exc.pse__End_Date__c != null) {
                Integer len = exc.pse__Date__c.daysBetween(exc.pse__End_Date__c) + 1;
                if (len == 7) {
                    // All per-day hours should be zero for the onsite gap week
                    Boolean allZero = (exc.pse__Monday_Hours__c == 0 && exc.pse__Tuesday_Hours__c == 0 && exc.pse__Wednesday_Hours__c == 0 && exc.pse__Thursday_Hours__c == 0 && exc.pse__Friday_Hours__c == 0 && exc.pse__Saturday_Hours__c == 0 && exc.pse__Sunday_Hours__c == 0);
                    if (allZero) {
                        foundWeekGap = true;
                        break;
                    }
                }
            }
        }
        System.assertEquals(true, foundWeekGap, 'Should find a 7-day onsite gap exception with zero hours');
    }

    @isTest
    static void testPercentSumLessAndGreaterThan100() {
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c WHERE pse__Start_Date__c = :Date.newInstance(2025,1,1) LIMIT 1];

        // Less than 100
        ScheduleHoursDistributor.ScheduleInput input1 = new ScheduleHoursDistributor.ScheduleInput();
        input1.scheduleId = schedule.Id;
        input1.startDate = Date.newInstance(2025, 1, 1);
        input1.endDate = Date.newInstance(2025, 7, 1);
        input1.numberOfHours = 200;
        input1.numberOfWorkDays = 5;
        input1.cat1Weeks = 11; input1.cat2Weeks = 8; input1.cat3Weeks = 6; input1.postWeeks = 4;
        input1.cat1Percentage = 10; input1.cat2Percentage = 10; input1.cat3Percentage = 10; input1.postPercentage = 10; // sum 40
        input1.onsiteStartDate = Date.newInstance(2025, 3, 1);
        input1.onsiteEndDate = Date.newInstance(2025, 3, 14);
        input1.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> r1 = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input1});
        System.assertEquals(1, r1.size());
        System.assertEquals(null, r1[0].errorMessage);
        System.assert(r1[0].scheduleExceptions.size() > 0, 'Should generate exceptions when percentages sum < 100');

        // Greater than 100
        ScheduleHoursDistributor.ScheduleInput input2 = input1;
        input2.cat1Percentage = 40; input2.cat2Percentage = 40; input2.cat3Percentage = 30; input2.postPercentage = 10; // sum 120
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> r2 = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input2});
        System.assertEquals(1, r2.size());
        System.assertEquals(null, r2[0].errorMessage);
        System.assert(r2[0].scheduleExceptions.size() > 0, 'Should generate exceptions when percentages sum > 100');
    }

    @isTest
    static void testMathWithoutExistingExceptions_TotalHoursMatch() {
        // Date range is a single work week Mon-Fri (2025-01-06 to 2025-01-10)
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c WHERE pse__Start_Date__c = :Date.newInstance(2025,1,1) LIMIT 1];
        input.scheduleId = schedule.Id;
        input.startDate = Date.newInstance(2025, 1, 6);
        input.endDate = Date.newInstance(2025, 1, 10);
        input.numberOfHours = 50;
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 1; input.cat2Weeks = 0; input.cat3Weeks = 0; input.postWeeks = 0;
        input.cat1Percentage = 60; input.cat2Percentage = 20; input.cat3Percentage = 15; input.postPercentage = 5;
        input.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage);

        // Sum total hours across generated exceptions by iterating each date in each exception
        Decimal totalHours = 0;
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            Date s = exc.pse__Date__c;
            Date e = exc.pse__End_Date__c == null ? s : exc.pse__End_Date__c;
            for (Date d = s; d <= e; d = d.addDays(1)) {
                Integer dow = d.toStartOfWeek().daysBetween(d) + 1;
                if (dow == 1) totalHours += (exc.pse__Monday_Hours__c == null ? 0 : exc.pse__Monday_Hours__c);
                if (dow == 2) totalHours += (exc.pse__Tuesday_Hours__c == null ? 0 : exc.pse__Tuesday_Hours__c);
                if (dow == 3) totalHours += (exc.pse__Wednesday_Hours__c == null ? 0 : exc.pse__Wednesday_Hours__c);
                if (dow == 4) totalHours += (exc.pse__Thursday_Hours__c == null ? 0 : exc.pse__Thursday_Hours__c);
                if (dow == 5) totalHours += (exc.pse__Friday_Hours__c == null ? 0 : exc.pse__Friday_Hours__c);
                if (dow == 6) totalHours += (exc.pse__Saturday_Hours__c == null ? 0 : exc.pse__Saturday_Hours__c);
                if (dow == 7) totalHours += (exc.pse__Sunday_Hours__c == null ? 0 : exc.pse__Sunday_Hours__c);
            }
        }

        // Allow small rounding differences
        System.assertEquals(input.numberOfHours.setScale(2), totalHours.setScale(2), 'Total distributed hours should equal requested hours');
    }

    @isTest
    static void testMathWithExistingHolidayExcludesDate_TotalHoursMatch() {
        // Use the single-day holiday inserted in @testSetup (2025-01-08)
        pse__Schedule_Exception__c holiday = [
            SELECT Id, pse__Date__c, pse__End_Date__c
            FROM pse__Schedule_Exception__c
            WHERE pse__Date__c = :Date.newInstance(2025, 1, 8)
            LIMIT 1
        ];

        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c WHERE pse__Start_Date__c = :Date.newInstance(2025,1,1) LIMIT 1];
        input.scheduleId = schedule.Id;
        input.startDate = Date.newInstance(2025, 1, 6);
        input.endDate = Date.newInstance(2025, 1, 10);
        input.numberOfHours = 50;
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 1; input.cat2Weeks = 0; input.cat3Weeks = 0; input.postWeeks = 0;
        input.cat1Percentage = 60; input.cat2Percentage = 20; input.cat3Percentage = 15; input.postPercentage = 5;
        input.existingExceptions = new List<pse__Schedule_Exception__c>{ holiday };

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage);

        // Verify holiday date not present in any generated exception ranges
        Date hol = holiday.pse__Date__c;
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            Date s = exc.pse__Date__c;
            Date e = exc.pse__End_Date__c == null ? s : exc.pse__End_Date__c;
            System.assertEquals(false, (s <= hol && e >= hol), 'Generated exceptions must not include holiday date');
        }

        // Sum total hours across generated exceptions
        Decimal totalHours = 0;
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            Date s = exc.pse__Date__c;
            Date e = exc.pse__End_Date__c == null ? s : exc.pse__End_Date__c;
            for (Date d = s; d <= e; d = d.addDays(1)) {
                Integer dow = d.toStartOfWeek().daysBetween(d) + 1;
                if (dow == 1) totalHours += (exc.pse__Monday_Hours__c == null ? 0 : exc.pse__Monday_Hours__c);
                if (dow == 2) totalHours += (exc.pse__Tuesday_Hours__c == null ? 0 : exc.pse__Tuesday_Hours__c);
                if (dow == 3) totalHours += (exc.pse__Wednesday_Hours__c == null ? 0 : exc.pse__Wednesday_Hours__c);
                if (dow == 4) totalHours += (exc.pse__Thursday_Hours__c == null ? 0 : exc.pse__Thursday_Hours__c);
                if (dow == 5) totalHours += (exc.pse__Friday_Hours__c == null ? 0 : exc.pse__Friday_Hours__c);
                if (dow == 6) totalHours += (exc.pse__Saturday_Hours__c == null ? 0 : exc.pse__Saturday_Hours__c);
                if (dow == 7) totalHours += (exc.pse__Sunday_Hours__c == null ? 0 : exc.pse__Sunday_Hours__c);
            }
        }

        System.assertEquals(input.numberOfHours.setScale(2), totalHours.setScale(2), 'Total distributed hours should still equal requested hours even with holidays');
    }
}