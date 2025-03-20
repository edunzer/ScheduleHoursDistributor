public with sharing class ScheduleHoursDistributor {

    @InvocableMethod(label='Generate Schedule Exceptions' description='Calculates and returns Schedule Exception records without inserting them.')
    public static List<ScheduleExceptionOutputWrapper> generateScheduleExceptions(List<ScheduleInput> inputList) {
        List<ScheduleExceptionOutputWrapper> outputList = new List<ScheduleExceptionOutputWrapper>();
        try {
            if (inputList.isEmpty()) {
                return new List<ScheduleExceptionOutputWrapper>();
            }

            ScheduleInput input = inputList[0];

            if (input.scheduleId == null) {
                return returnErrorWrapper('Error: Schedule ID cannot be null.');
            }
            if (input.startDate == null) {
                return returnErrorWrapper('Error: Start Date cannot be null.');
            }
            if (input.endDate == null) {
                return returnErrorWrapper('Error: End Date cannot be null.');
            }
            if (input.numberOfHours == null) {
                return returnErrorWrapper('Error: Number of Hours cannot be null.');
            }
            if (input.numberOfWorkDays == null) {
                return returnErrorWrapper('Error: Number of Work Days cannot be null.');
            }
            if (input.cat1Weeks == null || input.cat2Weeks == null || input.cat3Weeks == null || input.postWeeks == null) {
                return returnErrorWrapper('Error: Week values cannot be null.');
            }
            if (input.cat1Percentage == null || input.cat2Percentage == null || input.cat3Percentage == null || input.postPercentage == null) {
                return returnErrorWrapper('Error: Percentage values cannot be null.');
            }

            input.cat1Weeks = (input.cat1Weeks == null) ? 0 : input.cat1Weeks;
            input.cat2Weeks = (input.cat2Weeks == null) ? 0 : input.cat2Weeks;
            input.cat3Weeks = (input.cat3Weeks == null) ? 0 : input.cat3Weeks;
            input.postWeeks = (input.postWeeks == null) ? 0 : input.postWeeks;

            input.cat1StartDate = input.startDate;
            input.cat1EndDate = input.cat1StartDate.addDays(((Integer) input.cat1Weeks * 7) - 1);

            input.cat2StartDate = input.cat1EndDate.addDays(1);
            input.cat2EndDate = input.cat2StartDate.addDays(((Integer) input.cat2Weeks * 7) - 1);

            input.cat3StartDate = input.cat2EndDate.addDays(1);
            input.cat3EndDate = input.cat3StartDate.addDays(((Integer) input.cat3Weeks * 7) - 1);

            input.postStartDate = input.cat3EndDate.addDays(1);
            Date calculatedPostEnd = input.postStartDate.addDays(((Integer) input.postWeeks * 7) - 1);
            input.postEndDate = (calculatedPostEnd > input.endDate) ? input.endDate : calculatedPostEnd;

            input.cat1Percentage = (input.cat1Percentage == null) ? 0 : input.cat1Percentage;
            input.cat2Percentage = (input.cat2Percentage == null) ? 0 : input.cat2Percentage;
            input.cat3Percentage = (input.cat3Percentage == null) ? 0 : input.cat3Percentage;
            input.postPercentage = (input.postPercentage == null) ? 0 : input.postPercentage;

            input.numberOfWorkDays = (input.numberOfWorkDays == null) ? 0 : input.numberOfWorkDays;
            input.numberOfHours = (input.numberOfHours == null) ? 0 : input.numberOfHours;

            Decimal totalWeeks = input.cat1Weeks + input.cat2Weeks + input.cat3Weeks + input.postWeeks;

            if (totalWeeks == 0 || input.numberOfHours == 0) {
                return new List<ScheduleExceptionOutputWrapper>();
            }

            Set<Date> holidayDates = extractHolidayDates(input.existingExceptions);

            Integer cat1Holidays = countHolidaysInRange(holidayDates, input.cat1StartDate, input.cat1EndDate);
            Integer cat2Holidays = countHolidaysInRange(holidayDates, input.cat2StartDate, input.cat2EndDate);
            Integer cat3Holidays = countHolidaysInRange(holidayDates, input.cat3StartDate, input.cat3EndDate);
            Integer postHolidays = countHolidaysInRange(holidayDates, input.postStartDate, input.postEndDate);

            Integer cat1HolidayWeeks = cat1Holidays / input.numberOfWorkDays;
            Integer cat2HolidayWeeks = cat2Holidays / input.numberOfWorkDays;
            Integer cat3HolidayWeeks = cat3Holidays / input.numberOfWorkDays;
            Integer postHolidayWeeks = postHolidays / input.numberOfWorkDays;

            input.cat1Weeks = input.cat1Weeks - cat1HolidayWeeks;
            input.cat2Weeks = input.cat2Weeks - cat2HolidayWeeks;
            input.cat3Weeks = input.cat3Weeks - cat3HolidayWeeks;
            input.postWeeks = input.postWeeks - postHolidayWeeks;

            Decimal hoursPerWeekCat1 = (input.cat1Weeks > 0) ? ((input.cat1Percentage/100) * input.numberOfHours) / input.cat1Weeks : 0;
            Decimal hoursPerWeekCat2 = (input.cat2Weeks > 0) ? ((input.cat2Percentage/100) * input.numberOfHours) / input.cat2Weeks : 0;
            Decimal hoursPerWeekCat3 = (input.cat3Weeks > 0) ? ((input.cat3Percentage/100) * input.numberOfHours) / input.cat3Weeks : 0;
            Decimal hoursPerWeekPost = (input.postWeeks > 0) ? ((input.postPercentage/100) * input.numberOfHours) / input.postWeeks : 0;

            List<pse__Schedule_Exception__c> exceptions = generateExceptions(
                input, hoursPerWeekCat1, hoursPerWeekCat2, hoursPerWeekCat3, hoursPerWeekPost, holidayDates
            );

            outputList.add(new ScheduleExceptionOutputWrapper(exceptions, hoursPerWeekCat1, hoursPerWeekCat2, hoursPerWeekCat3, hoursPerWeekPost, null));
        } catch (Exception e) {
            outputList.add(new ScheduleExceptionOutputWrapper(new List<pse__Schedule_Exception__c>(), 0, 0, 0, 0, e.getMessage()));
        }
        return outputList;
    }

    private static List<ScheduleExceptionOutputWrapper> returnErrorWrapper(String errorMessage) {
        return new List<ScheduleExceptionOutputWrapper>{
            new ScheduleExceptionOutputWrapper(new List<pse__Schedule_Exception__c>(), 0, 0, 0, 0, errorMessage)
        };
    }

    private static Set<Date> extractHolidayDates(List<pse__Schedule_Exception__c> existingExceptions) {
        Set<Date> holidayDates = new Set<Date>();
        if (existingExceptions != null) {
            for (pse__Schedule_Exception__c exc : existingExceptions) {
                holidayDates.add(exc.pse__Date__c);
            }
        }
        return holidayDates;
    }

    private static Integer countHolidaysInRange(Set<Date> holidayDates, Date startDate, Date endDate) {
        Integer count = 0;
        for (Date d : holidayDates) {
            if (d >= startDate && d <= endDate) {
                count++;
            }
        }
        return count;
    } 
    
    private static Integer workDaysBetween(Date startDate, Date endDate, Set<Date> holidayDates) {
        Integer count = 0;
        for (Date d = startDate; d <= endDate; d = d.addDays(1)) {
            if (!holidayDates.contains(d)) {
                count++;
            }
        }
        return count;
    }    

    private static List<pse__Schedule_Exception__c> generateExceptions(
        ScheduleInput input, Decimal hoursPerWeekCat1, Decimal hoursPerWeekCat2, 
        Decimal hoursPerWeekCat3, Decimal hoursPerWeekPost, Set<Date> holidayDates
    ) {
        List<pse__Schedule_Exception__c> exceptions = new List<pse__Schedule_Exception__c>();
        Date currentStartDate = input.startDate;
        Integer workDays = input.numberOfWorkDays; 
        
        while (currentStartDate <= input.endDate) {
            Date currentEndDate = currentStartDate.addDays(6);
            if (currentEndDate > input.endDate) {
                currentEndDate = input.endDate;
            }

            Decimal hoursPerWeek;
            if (input.cat1Weeks > 0 && currentStartDate >= input.cat1StartDate && currentStartDate <= input.cat1EndDate) {
                hoursPerWeek = hoursPerWeekCat1;
            } else if (input.cat2Weeks > 0 && currentStartDate >= input.cat2StartDate && currentStartDate <= input.cat2EndDate) {
                hoursPerWeek = hoursPerWeekCat2;
            } else if (input.cat3Weeks > 0 && currentStartDate >= input.cat3StartDate && currentStartDate <= input.cat3EndDate) {
                hoursPerWeek = hoursPerWeekCat3;
            } else if (input.postWeeks > 0 && currentStartDate >= input.postStartDate && currentStartDate <= input.postEndDate) {
                hoursPerWeek = hoursPerWeekPost;
            } else {
                hoursPerWeek = 0;
            }

            List<Date> holidaysInWeek = new List<Date>();
            for (Date d = currentStartDate; d <= currentEndDate; d = d.addDays(1)) {
                if (holidayDates.contains(d)) {
                    holidaysInWeek.add(d);
                }
            }

            Integer workDaysInWeek = workDays - holidaysInWeek.size();
            Decimal hoursPerDay = (workDaysInWeek > 0) ? (hoursPerWeek / workDaysInWeek) : 0;

            if (!holidaysInWeek.isEmpty()) {
                Date segmentStart = currentStartDate;
                for (Date holiday : holidaysInWeek) {
                    if (segmentStart < holiday) {
                        exceptions.add(createScheduleException(
                            input.scheduleId, segmentStart, holiday.addDays(-1),
                            workDays, hoursPerDay
                        ));
                    }
                    segmentStart = holiday.addDays(1);
                }
                if (segmentStart <= currentEndDate) {
                    exceptions.add(createScheduleException(
                        input.scheduleId, segmentStart, currentEndDate,
                        workDays, hoursPerDay
                    ));
                }
            } else {
                exceptions.add(createScheduleException(
                    input.scheduleId, currentStartDate, currentEndDate,
                    workDays, hoursPerDay
                ));
            }

            currentStartDate = currentStartDate.addDays(7);
        }

        return exceptions;
    }
 
    private static pse__Schedule_Exception__c createScheduleException(Id scheduleId, Date startDate, Date endDate, Integer workDays, Decimal hoursPerDay) {
        return new pse__Schedule_Exception__c(
            pse__Schedule__c = scheduleId,
            pse__Date__c = startDate,
            pse__End_Date__c = endDate,
            pse__Monday_Hours__c = (workDays >= 1) ? hoursPerDay : 0,
            pse__Tuesday_Hours__c = (workDays >= 2) ? hoursPerDay : 0,
            pse__Wednesday_Hours__c = (workDays >= 3) ? hoursPerDay : 0,
            pse__Thursday_Hours__c = (workDays >= 4) ? hoursPerDay : 0,
            pse__Friday_Hours__c = (workDays >= 5) ? hoursPerDay : 0,
            pse__Saturday_Hours__c = (workDays >= 6) ? hoursPerDay : 0,
            pse__Sunday_Hours__c = (workDays >= 7) ? hoursPerDay : 0
        );
    }

    public class ScheduleExceptionOutputWrapper {
        @InvocableVariable(label='Schedule Exceptions' description='List of Schedule Exception records')
        public List<pse__Schedule_Exception__c> scheduleExceptions;
    
        @InvocableVariable(label='Hours Per Week - Cat1' description='Calculated hours per week for Category 1')
        public Decimal hoursPerWeekCat1;
    
        @InvocableVariable(label='Hours Per Week - Cat2' description='Calculated hours per week for Category 2')
        public Decimal hoursPerWeekCat2;
    
        @InvocableVariable(label='Hours Per Week - Cat3' description='Calculated hours per week for Category 3')
        public Decimal hoursPerWeekCat3;
    
        @InvocableVariable(label='Hours Per Week - Post' description='Calculated hours per week for Post Category')
        public Decimal hoursPerWeekPost;
    
        @InvocableVariable(label='Error Message' description='Error encountered during execution')
        public String errorMessage;
    
        public ScheduleExceptionOutputWrapper(List<pse__Schedule_Exception__c> exceptions, Decimal cat1Hours, Decimal cat2Hours, Decimal cat3Hours, Decimal postHours, String error) {
            this.scheduleExceptions = exceptions;
            this.hoursPerWeekCat1 = cat1Hours;
            this.hoursPerWeekCat2 = cat2Hours;
            this.hoursPerWeekCat3 = cat3Hours;
            this.hoursPerWeekPost = postHours;
            this.errorMessage = error;
        }
    }    

    public class ScheduleInput {
        @InvocableVariable(label='Schedule ID') public Id scheduleId;
        @InvocableVariable(label='Start Date') public Date startDate;
        @InvocableVariable(label='End Date') public Date endDate;
        @InvocableVariable(label='Number of Hours') public Decimal numberOfHours;
        @InvocableVariable(label='Number of Work Days') public Integer numberOfWorkDays;
        
        @InvocableVariable(label='Category 1 Weeks') public Decimal cat1Weeks;
        @InvocableVariable(label='Category 2 Weeks') public Decimal cat2Weeks;
        @InvocableVariable(label='Category 3 Weeks') public Decimal cat3Weeks;
        @InvocableVariable(label='Post Weeks') public Decimal postWeeks;

        @InvocableVariable(label='Category 1 Percentage') public Decimal cat1Percentage;
        @InvocableVariable(label='Category 2 Percentage') public Decimal cat2Percentage;
        @InvocableVariable(label='Category 3 Percentage') public Decimal cat3Percentage;
        @InvocableVariable(label='Post Percentage') public Decimal postPercentage;

        @InvocableVariable(label='Existing Schedule Exceptions') 
        public List<pse__Schedule_Exception__c> existingExceptions;

        public Date cat1StartDate;
        public Date cat1EndDate;
        public Date cat2StartDate;
        public Date cat2EndDate;
        public Date cat3StartDate;
        public Date cat3EndDate;
        public Date postStartDate;
        public Date postEndDate;
    }
}
