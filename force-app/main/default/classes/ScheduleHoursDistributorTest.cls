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
    static void testMultipleInputsProcessing_CurrentBehavior() {
        // The current implementation processes only the first input in the list.
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c LIMIT 1];

        ScheduleHoursDistributor.ScheduleInput input1 = new ScheduleHoursDistributor.ScheduleInput();
        input1.scheduleId = schedule.Id;
        input1.startDate = Date.newInstance(2025, 3, 1);
        input1.endDate = Date.newInstance(2025, 3, 7);
        input1.numberOfHours = Decimal.valueOf('40');
        input1.numberOfWorkDays = 5;
        input1.cat1Weeks = 1; input1.cat2Weeks = 0; input1.cat3Weeks = 0; input1.postWeeks = 0;
        input1.cat1Percentage = 100; input1.cat2Percentage = 0; input1.cat3Percentage = 0; input1.postPercentage = 0;
        input1.onsiteStartDate = null; input1.onsiteEndDate = null; input1.existingExceptions = new List<pse__Schedule_Exception__c>();

        ScheduleHoursDistributor.ScheduleInput input2 = new ScheduleHoursDistributor.ScheduleInput();
        input2.scheduleId = schedule.Id;
        input2.startDate = Date.newInstance(2025, 4, 1);
        input2.endDate = Date.newInstance(2025, 4, 7);
        input2.numberOfHours = Decimal.valueOf('35');
        input2.numberOfWorkDays = 5;
        input2.cat1Weeks = 1; input2.cat2Weeks = 0; input2.cat3Weeks = 0; input2.postWeeks = 0;
        input2.cat1Percentage = 100; input2.cat2Percentage = 0; input2.cat3Percentage = 0; input2.postPercentage = 0;
        input2.onsiteStartDate = null; input2.onsiteEndDate = null; input2.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleInput> inputs = new List<ScheduleHoursDistributor.ScheduleInput>{input1, input2};
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> results = ScheduleHoursDistributor.generateCategoryScheduleExceptions(inputs);

        // Current behavior: only one wrapper (first input) is processed
        System.assertEquals(1, results.size(), 'Current implementation processes only the first input');
        System.assertEquals(null, results[0].errorMessage, 'First input should produce no error with these values');
    }

    @isTest
    static void testAddSplitExceptions_MultiDaySplit_ConsecutiveSplits() {
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c LIMIT 1];
        Date segStart = Date.newInstance(2025,3,1);
        Date segEnd = Date.newInstance(2025,3,7);
        Set<Date> splits = new Set<Date>{ Date.newInstance(2025,3,3), Date.newInstance(2025,3,4) };

        List<pse__Schedule_Exception__c> allExceptions = new List<pse__Schedule_Exception__c>();
        List<pse__Schedule_Exception__c> catList = new List<pse__Schedule_Exception__c>();

        Decimal hoursPerDay = Decimal.valueOf('2');

        ScheduleHoursDistributor.addSplitExceptions(segStart, segEnd, hoursPerDay, 5, schedule.Id, segStart, segEnd, splits, allExceptions, catList);

        // Expect two segments: before the two-day split, and after
        System.assertEquals(2, catList.size(), 'Consecutive splits should yield two non-split segments');
        Integer totalRangeDays = segStart.daysBetween(segEnd) + 1;
        Integer summedDays = 0;
        for (pse__Schedule_Exception__c ex : catList) {
            Integer len = ex.pse__Date__c.daysBetween(ex.pse__End_Date__c) + 1;
            summedDays += len;
        }
        System.assertEquals(totalRangeDays - splits.size(), Integer.valueOf(summedDays), 'Summed days should equal total minus split days');
    }

    @isTest
    static void testOnsiteGapWeekBoundaries_PresentAsWeekException() {
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c LIMIT 1];

        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = schedule.Id;
        input.startDate = Date.newInstance(2025,3,1);
        input.endDate = Date.newInstance(2025,3,31);
        input.numberOfHours = Decimal.valueOf('80');
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 2; input.cat2Weeks = 2; input.cat3Weeks = 2; input.postWeeks = 0;
        input.cat1Percentage = 33; input.cat2Percentage = 33; input.cat3Percentage = 34; input.postPercentage = 0;
        // Choose an onsiteStartDate mid-week
        input.onsiteStartDate = Date.newInstance(2025,3,5);
        input.onsiteEndDate = Date.newInstance(2025,3,10);
        input.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage);

        // Compute expected onsite gap week start/end using same logic as implementation
        Integer dayOfWeek = input.onsiteStartDate.toStartOfWeek().daysBetween(input.onsiteStartDate) + 1;
        Integer daysToMonday = (dayOfWeek == 1) ? -6 : 2 - dayOfWeek;
        Date onsiteWeekStart = input.onsiteStartDate.addDays(daysToMonday);
        Date onsiteWeekEnd = onsiteWeekStart.addDays(6);

        Boolean foundOnsiteException = false;
        for (pse__Schedule_Exception__c ex : result[0].scheduleExceptions) {
            Date excEnd = ex.pse__End_Date__c == null ? ex.pse__Date__c : ex.pse__End_Date__c;
            if (ex.pse__Date__c == onsiteWeekStart && excEnd == onsiteWeekEnd) {
                // Week-level exception should have zero hours for weekdays
                System.assertEquals(Decimal.valueOf('0'), ex.pse__Monday_Hours__c);
                System.assertEquals(Decimal.valueOf('0'), ex.pse__Tuesday_Hours__c);
                System.assertEquals(Decimal.valueOf('0'), ex.pse__Wednesday_Hours__c);
                System.assertEquals(Decimal.valueOf('0'), ex.pse__Thursday_Hours__c);
                System.assertEquals(Decimal.valueOf('0'), ex.pse__Friday_Hours__c);
                foundOnsiteException = true;
            }
        }
        System.assertEquals(true, foundOnsiteException, 'Onsite week exception covering the gap should be present');
    }

    @isTest
    static void testPercentageSumOver100_NormalizesAndTotalsCorrectly() {
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c LIMIT 1];

        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = schedule.Id;
        input.startDate = Date.newInstance(2025,3,1);
        input.endDate = Date.newInstance(2025,3,21);
        input.numberOfHours = Decimal.valueOf('90');
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 1; input.cat2Weeks = 1; input.cat3Weeks = 1; input.postWeeks = 0;
        // Sum > 100
        input.cat1Percentage = 50; input.cat2Percentage = 50; input.cat3Percentage = 50; input.postPercentage = 0;
        input.onsiteStartDate = null; input.onsiteEndDate = null; input.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});
        System.assertEquals(1, result.size());
        System.assertEquals(null, result[0].errorMessage);

        // Sum actual hours from exceptions should equal numberOfHours
        Decimal actualTotal = Decimal.valueOf('0');
        for (pse__Schedule_Exception__c ex : result[0].scheduleExceptions) {
            Date s = ex.pse__Date__c;
            Date e = ex.pse__End_Date__c == null ? ex.pse__Date__c : ex.pse__End_Date__c;
            for (Date d = s; d <= e; d = d.addDays(1)) {
                Integer dow = d.toStartOfWeek().daysBetween(d) + 1;
                if (dow == 1) actualTotal += ex.pse__Monday_Hours__c == null ? 0 : ex.pse__Monday_Hours__c;
                if (dow == 2) actualTotal += ex.pse__Tuesday_Hours__c == null ? 0 : ex.pse__Tuesday_Hours__c;
                if (dow == 3) actualTotal += ex.pse__Wednesday_Hours__c == null ? 0 : ex.pse__Wednesday_Hours__c;
                if (dow == 4) actualTotal += ex.pse__Thursday_Hours__c == null ? 0 : ex.pse__Thursday_Hours__c;
                if (dow == 5) actualTotal += ex.pse__Friday_Hours__c == null ? 0 : ex.pse__Friday_Hours__c;
            }
        }

        System.assertEquals(input.numberOfHours.setScale(5), actualTotal.setScale(5), 'Total hours after normalization should equal input');
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
    static void testComputeValuesOnly() {
        // Controlled input where categories are 1 week each and no onsite/post, no holidays
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c LIMIT 1];

        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = schedule.Id;
        input.startDate = Date.newInstance(2025, 3, 1);
        input.endDate = Date.newInstance(2025, 3, 21);
        input.numberOfHours = Decimal.valueOf('90');
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 1;
        input.cat2Weeks = 1;
        input.cat3Weeks = 1;
        input.postWeeks = 0;
        input.cat1Percentage = 30;
        input.cat2Percentage = 30;
        input.cat3Percentage = 40;
        input.postPercentage = 0;
        input.onsiteStartDate = null;
        input.onsiteEndDate = null;
        input.existingExceptions = new List<pse__Schedule_Exception__c>();

        // Call the method under test
        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});
        System.assertEquals(null, result[0].errorMessage, 'Should be no error');

        // Reproduce the internal calculations to derive expected values
        Integer cat1Days = Integer.valueOf(input.cat1Weeks * 7);
        Integer cat2Days = Integer.valueOf(input.cat2Weeks * 7);
        Integer cat3Days = Integer.valueOf(input.cat3Weeks * 7);

        Date cat3End = input.endDate;
        Date cat3Start = cat3End.addDays(-cat3Days + 1);
        Date cat2End = cat3Start.addDays(-1);
        Date cat2Start = cat2End.addDays(-cat2Days + 1);
        Date cat1End = cat2Start.addDays(-1);
        Date cat1Start = cat1End.addDays(-cat1Days + 1);

        // Trim to input range (not needed here but kept for parity)
        Date cat1ActualStart = cat1Start > input.startDate ? cat1Start : input.startDate;
        Date cat1ActualEnd = cat1End < input.endDate ? cat1End : input.endDate;
        Date cat2ActualStart = cat2Start > input.startDate ? cat2Start : input.startDate;
        Date cat2ActualEnd = cat2End < input.endDate ? cat2End : input.endDate;
        Date cat3ActualStart = cat3Start > input.startDate ? cat3Start : input.startDate;
        Date cat3ActualEnd = cat3End < input.endDate ? cat3End : input.endDate;

        // No splits/holidays
        Set<Date> allSplits = new Set<Date>();

        Integer cat1Usable = ScheduleHoursDistributor.countUsableWorkdays(cat1ActualStart, cat1ActualEnd, allSplits);
        Integer cat2Usable = ScheduleHoursDistributor.countUsableWorkdays(cat2ActualStart, cat2ActualEnd, allSplits);
        Integer cat3Usable = ScheduleHoursDistributor.countUsableWorkdays(cat3ActualStart, cat3ActualEnd, allSplits);

        System.assertEquals(5, Integer.valueOf(cat1Usable), 'Cat1 usable days should be 5');
        System.assertEquals(5, Integer.valueOf(cat2Usable), 'Cat2 usable days should be 5');
        System.assertEquals(5, Integer.valueOf(cat3Usable), 'Cat3 usable days should be 5');

        // Percentages sum to 100, so hours per category are straightforward
        Decimal cat1Pct = input.cat1Percentage;
        Decimal cat2Pct = input.cat2Percentage;
        Decimal cat3Pct = input.cat3Percentage;

        Decimal cat1HoursPerDay = (cat1Usable > 0) ? ((cat1Pct/100) * input.numberOfHours) / cat1Usable : 0;
        Decimal cat2HoursPerDay = (cat2Usable > 0) ? ((cat2Pct/100) * input.numberOfHours) / cat2Usable : 0;
        Decimal cat3HoursPerDay = (cat3Usable > 0) ? ((cat3Pct/100) * input.numberOfHours) / cat3Usable : 0;

        // Expected totals
        Decimal expectedTotal = (cat1HoursPerDay * cat1Usable) + (cat2HoursPerDay * cat2Usable) + (cat3HoursPerDay * cat3Usable);
        System.assertEquals(input.numberOfHours, expectedTotal, 'Expected total hours should equal input numberOfHours');

        // Now compute actual total from generated exceptions by summing per-day fields across date ranges
        Decimal actualTotal = Decimal.valueOf('0');
        for (pse__Schedule_Exception__c ex : result[0].scheduleExceptions) {
            Date s = ex.pse__Date__c;
            Date e = ex.pse__End_Date__c == null ? ex.pse__Date__c : ex.pse__End_Date__c;
            for (Date d = s; d <= e; d = d.addDays(1)) {
                Integer dow = d.toStartOfWeek().daysBetween(d) + 1; // 1=Mon
                if (dow == 1) actualTotal += ex.pse__Monday_Hours__c == null ? 0 : ex.pse__Monday_Hours__c;
                if (dow == 2) actualTotal += ex.pse__Tuesday_Hours__c == null ? 0 : ex.pse__Tuesday_Hours__c;
                if (dow == 3) actualTotal += ex.pse__Wednesday_Hours__c == null ? 0 : ex.pse__Wednesday_Hours__c;
                if (dow == 4) actualTotal += ex.pse__Thursday_Hours__c == null ? 0 : ex.pse__Thursday_Hours__c;
                if (dow == 5) actualTotal += ex.pse__Friday_Hours__c == null ? 0 : ex.pse__Friday_Hours__c;
                if (dow == 6) actualTotal += ex.pse__Saturday_Hours__c == null ? 0 : ex.pse__Saturday_Hours__c;
                if (dow == 7) actualTotal += ex.pse__Sunday_Hours__c == null ? 0 : ex.pse__Sunday_Hours__c;
            }
        }

        System.assertEquals(expectedTotal.setScale(5), actualTotal.setScale(5), 'Computed total hours should match actual hours in exceptions');
    }

    @isTest
    static void testPercentageRedistribution() {
        // Controlled input where category percentages sum < 100 (10+10+10 = 30)
        pse__Schedule__c schedule = [SELECT Id FROM pse__Schedule__c LIMIT 1];

        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = schedule.Id;
        input.startDate = Date.newInstance(2025, 3, 1);
        input.endDate = Date.newInstance(2025, 3, 21);
        input.numberOfHours = Decimal.valueOf('90');
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 1;
        input.cat2Weeks = 1;
        input.cat3Weeks = 1;
        input.postWeeks = 0;
        // Low percentages to force redistribution
        input.cat1Percentage = 10;
        input.cat2Percentage = 10;
        input.cat3Percentage = 10;
        input.postPercentage = 0;
        input.onsiteStartDate = null;
        input.onsiteEndDate = null;
        input.existingExceptions = new List<pse__Schedule_Exception__c>();

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});
        System.assertEquals(null, result[0].errorMessage, 'Should be no error');
        System.assert(result[0].scheduleExceptions.size() > 0, 'Should generate exceptions');

        // There are 3 valid categories; original sum = 30, diff = 70, addEach = 70/3 -> expected per-category pct = 10 + 70/3 = 33.333...
        Decimal sumOrig = input.cat1Percentage + input.cat2Percentage + input.cat3Percentage;
        Decimal diff = 100 - sumOrig;
        Integer validCount = 3;
        Decimal addEach = diff / validCount;
        Decimal expectedCatPct = input.cat1Percentage + addEach; // same for each cat in this test

        // Each category covers 1 week (7 days) trimmed to weekdays -> usable days should be 5 each
        Integer expectedUsable = 5;
        // Expected hours per day per category = ((expectedPct/100) * totalHours) / usableDays
        Decimal expectedHoursPerDay = ((expectedCatPct / 100) * input.numberOfHours) / expectedUsable;

        // Expected total hours should equal input.numberOfHours
        Decimal expectedTotal = input.numberOfHours;

        // Compute actual total from generated exceptions and assert weekday hour values equal expectedHoursPerDay
        Decimal actualTotal = Decimal.valueOf('0');
        for (pse__Schedule_Exception__c ex : result[0].scheduleExceptions) {
            Date s = ex.pse__Date__c;
            Date e = ex.pse__End_Date__c == null ? ex.pse__Date__c : ex.pse__End_Date__c;
            for (Date d = s; d <= e; d = d.addDays(1)) {
                Integer dow = d.toStartOfWeek().daysBetween(d) + 1; // 1=Mon..7=Sun
                if (dow == 1) { actualTotal += ex.pse__Monday_Hours__c == null ? 0 : ex.pse__Monday_Hours__c; if (ex.pse__Monday_Hours__c != null) System.assertEquals(expectedHoursPerDay.setScale(5), ex.pse__Monday_Hours__c.setScale(5)); }
                if (dow == 2) { actualTotal += ex.pse__Tuesday_Hours__c == null ? 0 : ex.pse__Tuesday_Hours__c; if (ex.pse__Tuesday_Hours__c != null) System.assertEquals(expectedHoursPerDay.setScale(5), ex.pse__Tuesday_Hours__c.setScale(5)); }
                if (dow == 3) { actualTotal += ex.pse__Wednesday_Hours__c == null ? 0 : ex.pse__Wednesday_Hours__c; if (ex.pse__Wednesday_Hours__c != null) System.assertEquals(expectedHoursPerDay.setScale(5), ex.pse__Wednesday_Hours__c.setScale(5)); }
                if (dow == 4) { actualTotal += ex.pse__Thursday_Hours__c == null ? 0 : ex.pse__Thursday_Hours__c; if (ex.pse__Thursday_Hours__c != null) System.assertEquals(expectedHoursPerDay.setScale(5), ex.pse__Thursday_Hours__c.setScale(5)); }
                if (dow == 5) { actualTotal += ex.pse__Friday_Hours__c == null ? 0 : ex.pse__Friday_Hours__c; if (ex.pse__Friday_Hours__c != null) System.assertEquals(expectedHoursPerDay.setScale(5), ex.pse__Friday_Hours__c.setScale(5)); }
                if (dow == 6) { actualTotal += ex.pse__Saturday_Hours__c == null ? 0 : ex.pse__Saturday_Hours__c; }
                if (dow == 7) { actualTotal += ex.pse__Sunday_Hours__c == null ? 0 : ex.pse__Sunday_Hours__c; }
            }
        }

        // Compare totals with scale
        System.assertEquals(expectedTotal.setScale(5), actualTotal.setScale(5), 'Total hours after redistribution should equal input numberOfHours');
    }

    @isTest
    static void testMultiDayExistingExceptions() {
        // Retrieve the created Schedule
        pse__Schedule__c schedule = [SELECT Id, pse__Start_Date__c, pse__End_Date__c FROM pse__Schedule__c LIMIT 1];

        // Create input
        ScheduleHoursDistributor.ScheduleInput input = new ScheduleHoursDistributor.ScheduleInput();
        input.scheduleId = schedule.Id;
        input.startDate = Date.newInstance(2025, 3, 1);
        input.endDate = Date.newInstance(2025, 3, 31);
        input.numberOfHours = 160;
        input.numberOfWorkDays = 5;
        input.cat1Weeks = 2;
        input.cat2Weeks = 2;
        input.cat3Weeks = 2;
        input.postWeeks = 0;
        input.cat1Percentage = 33;
        input.cat2Percentage = 33;
        input.cat3Percentage = 34;
        input.postPercentage = 0;
        input.onsiteStartDate = null;
        input.onsiteEndDate = null;

        // Create a multi-day existing exception spanning 3/10 to 3/12 (inclusive)
        List<pse__Schedule_Exception__c> multi = new List<pse__Schedule_Exception__c>();
        multi.add(new pse__Schedule_Exception__c(
            pse__Date__c = Date.newInstance(2025, 3, 10),
            pse__End_Date__c = Date.newInstance(2025, 3, 12),
            pse__Monday_Hours__c = 0,
            pse__Tuesday_Hours__c = 0,
            pse__Wednesday_Hours__c = 0,
            pse__Thursday_Hours__c = 0,
            pse__Friday_Hours__c = 0,
            pse__Saturday_Hours__c = 0,
            pse__Sunday_Hours__c = 0
        ));
        input.existingExceptions = multi;

        List<ScheduleHoursDistributor.ScheduleExceptionOutputWrapper> result = ScheduleHoursDistributor.generateCategoryScheduleExceptions(new List<ScheduleHoursDistributor.ScheduleInput>{input});

        System.assertEquals(null, result[0].errorMessage, 'No error expected');
        System.assert(result[0].scheduleExceptions.size() > 0, 'Exceptions should be generated');

        // Ensure none of the generated exceptions covers any date from 2025-03-10..2025-03-12
        Set<Date> forbidden = new Set<Date>();
        for (Date d = Date.newInstance(2025,3,10); d <= Date.newInstance(2025,3,12); d = d.addDays(1)) forbidden.add(d);

        for (pse__Schedule_Exception__c exc : result[0].scheduleExceptions) {
            Date excEnd = exc.pse__End_Date__c == null ? exc.pse__Date__c : exc.pse__End_Date__c;
            for (Date d = exc.pse__Date__c; d <= excEnd; d = d.addDays(1)) {
                System.assertEquals(false, forbidden.contains(d), 'Generated exception should not cover multi-day holiday date: ' + d);
            }
        }
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