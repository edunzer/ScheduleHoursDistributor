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
    static void testMathFunctions() {
        // Retrieve the created Schedule
        pse__Schedule__c schedule = [SELECT Id, pse__Start_Date__c, pse__End_Date__c FROM pse__Schedule__c LIMIT 1];

        // Define a segment with a holiday in the middle
        Date segStart = Date.newInstance(2025, 3, 1);
        Date segEnd = Date.newInstance(2025, 3, 7);
        Set<Date> splits = new Set<Date>{ Date.newInstance(2025, 3, 4) };// holiday on 4th

        List<pse__Schedule_Exception__c> allExceptions = new List<pse__Schedule_Exception__c>();
        List<pse__Schedule_Exception__c> catList = new List<pse__Schedule_Exception__c>();

        Decimal hoursPerDay = Decimal.valueOf('2.5');

        // Call addSplitExceptions to split the segment around the holiday
        ScheduleHoursDistributor.addSplitExceptions(
            segStart, segEnd, hoursPerDay, 5, schedule.Id, schedule.pse__Start_Date__c, schedule.pse__End_Date__c, splits, allExceptions, catList
        );

        // Expect two exceptions: before holiday and after holiday
        System.assertEquals(2, catList.size(), 'Segment with single split should produce two exceptions');
        System.assertEquals(2, allExceptions.size(), 'All exceptions should contain the two created exceptions');

        // Sum of days covered by exceptions should equal seg range minus splits
        Integer summedDays = 0;
        for (pse__Schedule_Exception__c ex : catList) {
            Integer len = ex.pse__Date__c.daysBetween(ex.pse__End_Date__c) + 1;
            summedDays += len;
            // Verify hours fields for Mon-Fri are set to hoursPerDay (workDays = 5)
            System.assertEquals(hoursPerDay, ex.pse__Monday_Hours__c, 'Monday hours should equal hoursPerDay');
            System.assertEquals(hoursPerDay, ex.pse__Tuesday_Hours__c, 'Tuesday hours should equal hoursPerDay');
            System.assertEquals(hoursPerDay, ex.pse__Wednesday_Hours__c, 'Wednesday hours should equal hoursPerDay');
            System.assertEquals(hoursPerDay, ex.pse__Thursday_Hours__c, 'Thursday hours should equal hoursPerDay');
            System.assertEquals(hoursPerDay, ex.pse__Friday_Hours__c, 'Friday hours should equal hoursPerDay');
            System.assertEquals(Decimal.valueOf('0'), ex.pse__Saturday_Hours__c, 'Saturday hours should be 0');
            System.assertEquals(Decimal.valueOf('0'), ex.pse__Sunday_Hours__c, 'Sunday hours should be 0');
        }

        // The total non-split days should be seg length minus number of split days (1)
        Integer totalRangeDays = segStart.daysBetween(segEnd) + 1;
        System.assertEquals(totalRangeDays - splits.size(), Integer.valueOf(summedDays), 'Summed days should equal total days minus splits');

        // Validate countUsableWorkdays matches manual weekday counting (excluding splits)
        Integer counted = ScheduleHoursDistributor.countUsableWorkdays(segStart, segEnd, splits);
        Integer expectedCount = 0;
        for (Date d = segStart; d <= segEnd; d = d.addDays(1)) {
            if (ScheduleHoursDistributor.isWeekday(d) && !splits.contains(d)) expectedCount++;
        }
        System.assertEquals(expectedCount, counted, 'countUsableWorkdays should match manual weekday count excluding splits');

        // Validate total hours computed from usable days matches hoursPerDay * usableDays
        Decimal totalHoursFromCount = hoursPerDay * counted;
        // Compute total hours represented by the exceptions (only count weekdays)
        Decimal totalHoursFromExceptions = Decimal.valueOf('0');
        for (pse__Schedule_Exception__c ex : catList) {
            for (Date d = ex.pse__Date__c; d <= ex.pse__End_Date__c; d = d.addDays(1)) {
                if (ScheduleHoursDistributor.isWeekday(d)) {
                    totalHoursFromExceptions += hoursPerDay;
                }
            }
        }
        System.assertEquals(totalHoursFromCount, totalHoursFromExceptions, 'Total hours computed from usable days should match hours represented by exceptions');
    }

    @isTest
    static void testGenerateScheduleExceptions() {
        // Retrieve the created Schedule
        pse__Schedule__c schedule = [SELECT Id, pse__Start_Date__c, pse__End_Date__c, pse__Scheduled_Hours__c FROM pse__Schedule__c LIMIT 1];
        
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
    static void testGenerateScheduleExceptionsWithExistingExceptions() {
        // Retrieve the created Schedule
        pse__Schedule__c schedule = [SELECT Id, pse__Start_Date__c, pse__End_Date__c, pse__Scheduled_Hours__c FROM pse__Schedule__c LIMIT 1];

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
        // Onsite dates
        input.onsiteStartDate = Date.newInstance(2025, 3, 1);
        input.onsiteEndDate = Date.newInstance(2025, 3, 14);

        // Provide existing exceptions (holidays) - these are not inserted, just supplied to the method
        List<pse__Schedule_Exception__c> holidays = new List<pse__Schedule_Exception__c>();
        // Pick a few dates within the schedule range to act as holidays
        holidays.add(new pse__Schedule_Exception__c(
            pse__Date__c = Date.newInstance(2025, 3, 3),
            pse__End_Date__c = Date.newInstance(2025, 3, 3),
            pse__Monday_Hours__c = 0,
            pse__Tuesday_Hours__c = 0,
            pse__Wednesday_Hours__c = 0,
            pse__Thursday_Hours__c = 0,
            pse__Friday_Hours__c = 0,
            pse__Saturday_Hours__c = 0,
            pse__Sunday_Hours__c = 0
        ));
        holidays.add(new pse__Schedule_Exception__c(
            pse__Date__c = Date.newInstance(2025, 4, 15),
            pse__End_Date__c = Date.newInstance(2025, 4, 15),
            pse__Monday_Hours__c = 0,
            pse__Tuesday_Hours__c = 0,
            pse__Wednesday_Hours__c = 0,
            pse__Thursday_Hours__c = 0,
            pse__Friday_Hours__c = 0,
            pse__Saturday_Hours__c = 0,
            pse__Sunday_Hours__c = 0
        ));
        holidays.add(new pse__Schedule_Exception__c(
            pse__Date__c = Date.newInstance(2025, 5, 5),
            pse__End_Date__c = Date.newInstance(2025, 5, 5),
            pse__Monday_Hours__c = 0,
            pse__Tuesday_Hours__c = 0,
            pse__Wednesday_Hours__c = 0,
            pse__Thursday_Hours__c = 0,
            pse__Friday_Hours__c = 0,
            pse__Saturday_Hours__c = 0,
            pse__Sunday_Hours__c = 0
        ));
        input.existingExceptions = holidays;

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});

        // Basic assertions
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Only one result should be returned');
        System.assert(result[0].scheduleExceptions.size() > 0, 'Schedule exceptions should be generated');
        System.assertEquals(null, result[0].errorMessage, 'There should be no error messages');

        // Ensure none of the generated exceptions covers a holiday date
        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            for (pse__Schedule_Exception__c hol : holidays) {
                // If exception has an end date, check range; otherwise check start only
                Date excEnd = exc.pse__End_Date__c == null ? exc.pse__Date__c : exc.pse__End_Date__c;
                Boolean covers = (exc.pse__Date__c <= hol.pse__Date__c && hol.pse__Date__c <= excEnd);
                System.assertEquals(false, covers, 'Generated exception should not cover holiday ' + hol.pse__Date__c);
            }
        }
    }
}