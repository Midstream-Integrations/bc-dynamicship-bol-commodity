reportextension 50230 "MID DSHIP Bill of Lading" extends "DSHIP Bill of Lading"
{
    dataset
    {
        add(orderBuffer)
        {
            column(MID_ShipProNumber; MID_ProNumber)
            {
            }
            column(MID_ShipProNumberBarcode; TempProNumberBarcode.Picture)
            {
            }
        }
        modify(orderBuffer)
        {
            trigger OnAfterAfterGetRecord()
            var
                BarcodeGen: Codeunit "IWX Barcode Generation";
                TempBlob: Codeunit "Temp Blob";
                InStr: InStream;
                OutStr: OutStream;
            begin
                MID_ProNumber := '';
                Clear(TempProNumberBarcode);
                MID_ProNumber := GetSourceDocumentProNumber();
                if MID_ProNumber = '' then
                    exit;
                Clear(TempBlob);
                BarcodeGen.Generate39Barcode(TempBlob, MID_ProNumber, 100, 20);
                TempProNumberBarcode.Picture.CreateOutStream(OutStr);
                TempBlob.CreateInStream(InStr);
                CopyStream(OutStr, InStr);
            end;
        }
        add(PackagesPerCommodity)
        {
            column(MID_perCommDescription; MID_perCommDescription)
            {
            }
            column(MID_perCommNMFC; MID_perCommNMFC)
            {
            }
            column(MID_perCommFreightClass; MID_perCommFreightClass)
            {
            }
        }
        modify(PackagesPerCommodity)
        {
            trigger OnAfterAfterGetRecord()
            var
                DocumentPlate: Record "IWX LP Header";
            begin
                MID_perCommDescription := '';
                MID_perCommNMFC := '';
                MID_perCommFreightClass := '';
                if not SetDocumentPlateFilter(DocumentPlate) then
                    exit;
                CommodityMgt.BuildCommodityLine(DocumentPlate, PackagesPerCommodity, MID_perCommDescription, MID_perCommNMFC, MID_perCommFreightClass);
            end;
        }
    }

    // No layout is shipped: add the MID_* columns to your own Bill of Lading layout (see README).

    var
        TempProNumberBarcode: Record "Company Information" temporary;
        DSHIPPackageManagement: Codeunit "DSHIP Package Management";
        CommodityMgt: Codeunit "MID BOL Commodity Mgt.";
        MID_perCommDescription: Text;
        MID_perCommFreightClass: Text;
        MID_perCommNMFC: Text;
        MID_ProNumber: Text;

    /// <summary>
    /// Returns the pro number keyed on the sales order behind this Bill of Lading, or a blank string when
    /// none is recorded. License plates are deliberately not consulted: their Package Tracking No. is
    /// carrier data written by labelling and can hold a value long before a carrier is chosen for this
    /// shipment, so the pro number is taken only from where a person actually enters it.
    /// </summary>
    local procedure GetSourceDocumentProNumber(): Text
    var
        SalesHeader: Record "Sales Header";
        SalesShipmentHeader: Record "Sales Shipment Header";
        WarehouseShipmentLine: Record "Warehouse Shipment Line";
        DocumentNo: Code[20];
    begin
        if orderBuffer."Document No." = '' then
            exit('');
        DocumentNo := CopyStr(orderBuffer."Document No.", 1, MaxStrLen(DocumentNo));

        // Printed from the sales order itself.
        if SalesHeader.Get(SalesHeader."Document Type"::Order, DocumentNo) then
            exit(SalesHeader."Package Tracking No.");

        // Printed from a warehouse shipment - hop to the order behind it.
        WarehouseShipmentLine.SetRange("No.", DocumentNo);
        WarehouseShipmentLine.SetRange("Source Document", WarehouseShipmentLine."Source Document"::"Sales Order");
        WarehouseShipmentLine.SetLoadFields("Source No.");
        if WarehouseShipmentLine.FindFirst() then
            if SalesHeader.Get(SalesHeader."Document Type"::Order, WarehouseShipmentLine."Source No.") then
                exit(SalesHeader."Package Tracking No.");

        // Printed after posting - the order is gone and the number rode along to the posted shipment.
        if SalesShipmentHeader.Get(DocumentNo) then
            exit(SalesShipmentHeader."Package Tracking No.");

        exit('');
    end;

    /// <summary>
    /// Filters DocumentPlate to the license plates of the document being printed. Returns false when the
    /// document cannot be identified, in which case the caller must report nothing rather than fall back
    /// on whatever the filter happens to match.
    /// </summary>
    /// <remarks>
    /// Without the blank guard the filter degenerates to 'Source Document = 0, Source No. = ""', which
    /// matches license plates that were never assigned to a document - old test plates and the like -
    /// and any Find against that set returns records belonging to no shipment at all. This is now only
    /// used for the commodity block; the pro number no longer reads license plates.
    /// </remarks>
    local procedure SetDocumentPlateFilter(var DocumentPlate: Record "IWX LP Header"): Boolean
    var
        LPSourceDoc: Option;
    begin
        DocumentPlate.Reset();
        if orderBuffer."Document No." = '' then
            exit(false);
        DSHIPPackageManagement.getLPSrcTypeFromDShipDocType(orderBuffer."Document Type", LPSourceDoc);
        DocumentPlate.SetRange("Source Document", LPSourceDoc);
        DocumentPlate.SetRange("Source No.", orderBuffer."Document No.");
        exit(true);
    end;
}
