table 50231 "MID BOL Commodity Setup"
{
    Caption = 'BOL Commodity Setup';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Primary Key"; Code[10]) { Caption = 'Primary Key'; }
        field(2; "Commodity Line Format"; Text[100])
        {
            Caption = 'Commodity Line Format';
            InitValue = 'Qty: %1 %2 - %4';
        }
    }

    keys
    {
        key(PK; "Primary Key") { Clustered = true; }
    }
}

page 50231 "MID BOL Commodity Setup"
{
    Caption = 'BOL Commodity Setup';
    PageType = Card;
    SourceTable = "MID BOL Commodity Setup";
    ApplicationArea = All;
    UsageCategory = Administration;
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(content)
        {
            group(General)
            {
                Caption = 'General';
                field("Commodity Line Format"; Rec."Commodity Line Format")
                {
                    ToolTip = 'How each item is printed in a commodity line on the Bill of Lading. Placeholders: %1 quantity, %2 item no., %3 item no. 2, %4 description, %5 base unit of measure. Example: %1 %5 %4 (%2).';
                }
            }
        }
    }

    trigger OnOpenPage()
    begin
        if not Rec.Get() then begin
            Rec.Init();
            Rec.Insert();
        end;
    end;
}
