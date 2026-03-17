@isTest
private class SetListReorderControllerTest {

    @testSetup
    static void setup() {
        Song__c song1 = new Song__c(Name = 'Song A');
        Song__c song2 = new Song__c(Name = 'Song B');
        insert new List<Song__c>{ song1, song2 };

        Set_List__c setList = new Set_List__c(Name = 'Test Set List');
        insert setList;

        insert new List<Set_List_Song__c>{
            new Set_List_Song__c(Set_List__c = setList.Id, Song__c = song1.Id, Order_Number__c = 1),
            new Set_List_Song__c(Set_List__c = setList.Id, Song__c = song2.Id, Order_Number__c = 2)
        };
    }

    @isTest
    static void testGetSetListSongsNull() {
        List<SetListReorderController.SetListSongDTO> result = SetListReorderController.getSetListSongs(null);
        System.assertEquals(0, result.size());
    }

    @isTest
    static void testGetSetListSongs() {
        Set_List__c setList = [SELECT Id FROM Set_List__c LIMIT 1];
        List<SetListReorderController.SetListSongDTO> result = SetListReorderController.getSetListSongs(setList.Id);
        System.assertEquals(2, result.size());
        System.assertNotEquals(null, result[0].name);
        System.assertNotEquals(null, result[0].currentOrder);
    }

    @isTest
    static void testUpdateOrdersOrderedNull() {
        SetListReorderController.updateOrdersOrdered(null);
    }

    @isTest
    static void testUpdateOrdersOrderedEmpty() {
        SetListReorderController.updateOrdersOrdered(new List<Id>());
    }

    @isTest
    static void testUpdateOrdersOrdered() {
        List<Set_List_Song__c> songs = [SELECT Id FROM Set_List_Song__c ORDER BY Order_Number__c ASC];
        List<Id> reversed = new List<Id>{ songs[1].Id, songs[0].Id };

        SetListReorderController.updateOrdersOrdered(reversed);

        List<Set_List_Song__c> updated = [SELECT Id, Order_Number__c FROM Set_List_Song__c ORDER BY Order_Number__c ASC];
        System.assertEquals(1, updated[0].Order_Number__c);
        System.assertEquals(2, updated[1].Order_Number__c);
    }
}
