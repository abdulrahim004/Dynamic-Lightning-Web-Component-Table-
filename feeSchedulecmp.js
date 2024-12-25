import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import displayFeeScheduleData from '@salesforce/apex/CreationOfFeeSchedule.displayFeeScheduleData';
import { updateRecord } from 'lightning/uiRecordApi';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import { deleteRecord } from 'lightning/uiRecordApi';
import opportunity_service_OBJECT from "@salesforce/schema/OpportunityService__c";
import FEE_TYPE_FIELD from '@salesforce/schema/OpportunityService__c.Fee_Type__c';


export default class FeeScheduleTable extends LightningElement {
    @api recordId;
    @api projectLabel;
    opportunityservicerecordtypeId;
    feetypes; // Corrected variable name for fee types

    @track columns = [];
    @track rows = [];
    @track isLoading = true;
    wiredData;
    isExternalTemplate=true;


    

    @wire(getObjectInfo, { objectApiName: opportunity_service_OBJECT })
    results({ error, data }) {
        if (data) {
            this.opportunityservicerecordtypeId = data.defaultRecordTypeId; // Corrected variable name
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.opportunityservicerecordtypeId = undefined;
        }
    }

    @wire(getPicklistValues, { recordTypeId: "$opportunityservicerecordtypeId", fieldApiName: FEE_TYPE_FIELD })
    picklistResults({ error, data }) {
        if (data) {
            this.feetypes = data.values; // Corrected variable name
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.feetypes = undefined;
        }
    }

    @wire(displayFeeScheduleData, { projectLabel: '$projectLabel', recordId: '$recordId' })
    wiredFeeSchedule(response) {
        this.isLoading = true;
        this.wiredData = response;
        const { error, data } = response;
    
        if (data) {
            console.log('Retrieved Data:', data);
    
            // Initialize isExternalTemplate as false
            this.isExternalTemplate = false;
    
            // Map Columns
            this.columns = data.columns.map(column => {
                let isExternal = false;
    
                // Check if the column's feetype is 'External'
                if (column.projecttype === 'External') {
                    //isExternal = true;
                    this.isExternalTemplate = true; // If any column is 'External', set the template flag to true
                }
    
                return {
                    label: column.label || '',
                    fieldName: column.fieldName || '',
                    type: column.type || 'text',
                    oppserviceId: column.opportunityserviceid,
                    servicetotal: column.oppservicetotal || 0,
                    feeType: column.feetype || '',
                    isExternal: isExternal, // Dynamically set isExternal
                };
            });
    
            console.log('Processed Columns:', this.columns);
    
            // Map Rows
            this.rows = (data?.rows || []).map(row => ({
                id: row?.id,
                billingDate: row?.BillingDate || '',
                rowtotal: row?.rowtotal || '',
                fields: this.columns.map(column => ({
                    name: column.fieldName,
                    feeScheduleTotal: row[column.fieldName]?.[''] || '',
                    value: row[column.fieldName]?.['Price__c'] || '',
                    feescheduleid: row[column.fieldName]?.['FeeScheduleId'],
                    id: row[column.fieldName]?.['FeeScheduleOpportunityServiceId'],
                   
                })),
            }));
    
            this.isLoading = false;
            console.log('Processed Rows:', this.rows);
        } else if (error) {
            console.error('Error in wiredFeeSchedule:', JSON.stringify(error));
            this.isLoading = false;
        }
    }
    



    // Method to update searchKey when user types
   
    handleInputChange(event) {
        const rowId = event.target.dataset.id;
        const fieldName = event.target.dataset.field;
        const value = parseFloat(event.target.value) || 0;

        if (value < 0 || isNaN(value)) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Please enter a valid positive number.',
                    variant: 'error',
                })
            );
            return;
        }

        console.log('Updating row:', rowId, 'Field:', fieldName, 'Value:', value);

        const updatedData = {
            fields: {
                Id: rowId,
                Price__c: value,
            },
        };

        console.log('Updated Data:', updatedData);

        updateRecord(updatedData)
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Record updated successfully.',
                        variant: 'success',
                    })
                );
                return refreshApex(this.wiredData);
            })
            .catch(error => {
                console.error('Error saving record:', JSON.stringify(error));
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || 'An error occurred while saving the record.',
                        variant: 'error',
                    })
                );
            });
    }


    handleAccountSelection(event) {
        const selectedAccount = event.target.value;  // Get the selected Account value
        const oppServiceIds = event.target.dataset.id;  // Get the Opportunity Service ID
        
    
        console.log('Opportunity Service ID:', oppServiceIds, 'New Account:', selectedAccount);
    
        // Validate that the required data is present
        if (!oppServiceIds || !selectedAccount) {
            console.error('Missing required data for Account update.');
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Unable to update Account. Required data is missing.',
                    variant: 'error',
                })
            );
            return;
        }
    
        console.log('Updating Account for Opportunity Service:', oppServiceIds, 'New Account:', selectedAccount);
    
        // Prepare the record data for update
        const updatedData = {
            fields: {
                Id: oppServiceIds,
                Account__c: selectedAccount, // Update Account__c field
            },
        };
    
        // Perform the record update
        updateRecord(updatedData)
            .then(() => {
                console.log('Account updated successfully for ID:', oppServiceIds);
    
                // Show success toast notification
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Account updated successfully.',
                        variant: 'success',
                    })
                );
    
                // Refresh the wired data to reflect changes in the UI
                return refreshApex(this.wiredData);
            })
            .catch(error => {
                // Log and display error message
                console.error('Error updating Account:', error);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || 'An error occurred while updating the Account.',
                        variant: 'error',
                    })
                );
            });
    }
    
    handleFeeTypeChange(event) {
        // Extracting dataset ID and new Fee Type value from the event
        const oppServiceId =event.target.dataset.id;
        const newFeeType = event.detail.value;
        console.log('Opportunity Service ID:', oppServiceId, 'New Fee Type:', newFeeType);
        // Validate that the required data is present
        if (!oppServiceId || !newFeeType) {
            console.error('Missing required data for Fee Type update.');
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Unable to update Fee Type. Required data is missing.',
                    variant: 'error',
                })
            );
            return;
        }
    
        console.log('Updating Fee Type for Opportunity Service:', oppServiceId, 'New Fee Type:', newFeeType);
    
        // Prepare the record data for update
        const updatedData = {
            fields: {
                Id: oppServiceId,
                Fee_type__c: newFeeType,
            },
        };
    
        // Perform the record update
        updateRecord(updatedData)
            .then(() => {
                console.log('Fee Type updated successfully for ID:', oppServiceId);
    
                // Show success toast notification
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Fee Type updated successfully.',
                        variant: 'success',
                    })
                );
    
                // Refresh the wired data to reflect changes in the UI
                return refreshApex(this.wiredData);
            })
            .catch(error => {
                // Log and display error message
                console.error('Error updating Fee Type:', error);
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || 'An error occurred while updating Fee Type.',
                        variant: 'error',
                    })
                );
            });
    }
    
    handleDeleteFeeSchedule(event) {
        const rowId = event.target.dataset.id;

        if (!rowId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Unable to determine row ID for deletion.',
                    variant: 'error',
                })
            );
            return;
        }

        deleteRecord(rowId)
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Fee Schedule deleted successfully.',
                        variant: 'success',
                    })
                );
                return refreshApex(this.wiredData);
            })
            .catch(error => {
                console.error('Error deleting record:', JSON.stringify(error));
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || 'An error occurred while deleting the record.',
                        variant: 'error',
                    })
                );
            });
    }
}
