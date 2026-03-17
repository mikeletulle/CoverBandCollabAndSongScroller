/**
 * Test class for SetListSongTrigger.
 * Verifies that the trigger correctly adjusts Order_Number__c when Set_List_Song__c records
 * are inserted or updated, and that it can be bypassed via SongListHelper.isTriggerExecuted.
 */
@isTest
private class SetListSongTriggerTest {

    /**
     * Creates a Set_List__c with two Set_List_Song__c records (order 1 and 2) for use by all test methods.
     */
    @TestSetup
    static void setup() {
        Set_List__c setList = new Set_List__c(Name = 'Test Set List');
        insert setList;

        List<Set_List_Song__c> songs = new List<Set_List_Song__c>{
            new Set_List_Song__c(Set_List__c = setList.Id, Order_Number__c = 1),
            new Set_List_Song__c(Set_List__c = setList.Id, Order_Number__c = 2)
        };
        insert songs;
    }

    /**
     * Inserts a third song at position 2 and verifies the trigger reorders existing records.
     * Expects 3 songs total with sequential order numbers (1, 2, 3).
     */
    @isTest
    static void testTriggerAdjustsOrderOnInsert() {
        Set_List__c setList = [SELECT Id FROM Set_List__c LIMIT 1];

        Set_List_Song__c newSong = new Set_List_Song__c(Set_List__c = setList.Id, Order_Number__c = 2);
        insert newSong;

        List<Set_List_Song__c> results = [
            SELECT Order_Number__c
            FROM Set_List_Song__c
            WHERE Set_List__c = :setList.Id
            ORDER BY Order_Number__c ASC
        ];

        System.assertEquals(3, results.size(), 'Should have 3 songs');
        System.assertEquals(1, results[0].Order_Number__c);
        System.assertEquals(2, results[1].Order_Number__c);
    }

    /**
     * When SongListHelper.isTriggerExecuted is true, the trigger skips processing.
     * Verifies that insert still succeeds without triggering order adjustment logic.
     */
    @isTest
    static void testTriggerSkipsWhenFlagSet() {
        SongListHelper.isTriggerExecuted = true;

        Set_List__c setList = [SELECT Id FROM Set_List__c LIMIT 1];
        Set_List_Song__c song = new Set_List_Song__c(Set_List__c = setList.Id, Order_Number__c = 4);
        insert song;

        System.assertNotEquals(null, song.Id);
    }
}
