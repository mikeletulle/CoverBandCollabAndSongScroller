trigger SetListSongTrigger on Set_List_Song__c (after insert, after update) {
    if (SetListReorderController.isBulkReorderInProgress) {
        return;
    }
    if (SongListHelper.isTriggerExecuted) {
        return;
    }
    SongListHelper.isTriggerExecuted = true;

    if (Trigger.isAfter) {
        Set<Id> affectedSetListIds = new Set<Id>();
        for (Set_List_Song__c song : Trigger.new) {
            if (song.Set_List__c != null) {
                affectedSetListIds.add(song.Set_List__c);
            }
        }

        List<Set_List_Song__c> songsToUpdate = new List<Set_List_Song__c>();

        for (Id setListId : affectedSetListIds) {
            List<Set_List_Song__c> allSongs = [
                SELECT Id, Order_Number__c
                FROM Set_List_Song__c
                WHERE Set_List__c = :setListId
                ORDER BY Order_Number__c ASC NULLS LAST, CreatedDate ASC, Id ASC
            ];

            for (Integer i = 0; i < allSongs.size(); i++) {
                Decimal expectedOrder = Decimal.valueOf(i + 1);
                if (allSongs[i].Order_Number__c != expectedOrder) {
                    allSongs[i].Order_Number__c = expectedOrder;
                    songsToUpdate.add(allSongs[i]);
                }
            }
        }

        if (!songsToUpdate.isEmpty()) {
            update songsToUpdate;
        }
    }
}