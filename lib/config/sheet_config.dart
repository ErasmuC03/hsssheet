import 'package:flutter/material.dart';

class SheetColumn {
  final String key;
  final String label;
  final double width;
  final Color headerColor;
  final bool isCompletionField;

  const SheetColumn({
    required this.key,
    required this.label,
    this.width = 170,
    this.headerColor = const Color(0xFFE0E0E0),
    this.isCompletionField = false,
  });
}

class SheetConfig {
  final String id;
  final String title;
  final String shortTitle;
  final String? completedField;
  final List<SheetColumn> columns;

  const SheetConfig({
    required this.id,
    required this.title,
    required this.shortTitle,
    required this.columns,
    this.completedField,
  });
}

const greyHeader = Color(0xFFD9D9D9);
const blueHeader = Color(0xFFB4C7E7);
const creamHeader = Color(0xFFFFF2CC);
const yellowHeader = Color(0xFFFFFF00);
const redHeader = Color(0xFFFF0000);
const greenHeader = Color(0xFF92D050);
const whiteHeader = Color(0xFFFFFFFF);

const SheetConfig paedCnsConfig = SheetConfig(
  id: 'paed_cns',
  shortTitle: 'Paed & CNS',
  title: 'MHS & WPS CDS Paediatrician & CNS client questionnaire tracking spreadsheet',
  completedField: 'qUploadedToGenieDate',
  columns: [
    SheetColumn(
      key: 'clientName',
      label: 'Client name\n(Surname, first name)',
      width: 220,
      headerColor: greyHeader,
    ),
    SheetColumn(
      key: 'clientDob',
      label: 'Client DOB',
      width: 130,
      headerColor: greyHeader,
    ),
    SheetColumn(
      key: 'umrn',
      label: 'UMRN',
      width: 120,
      headerColor: greyHeader,
    ),
    SheetColumn(
      key: 'localCdsCatchmentSite',
      label: 'Local CDS catchment site',
      width: 180,
      headerColor: blueHeader,
    ),
    SheetColumn(
      key: 'paediatricianClinic',
      label: 'Paediatrician\nor Clinic i.e. Paed-CNS Rv Clinic etc',
      width: 260,
      headerColor: blueHeader,
    ),
    SheetColumn(
      key: 'questionnairePlatform',
      label: 'Questionnaire\nplatform',
      width: 150,
      headerColor: creamHeader,
    ),
    SheetColumn(
      key: 'questionnaireType',
      label: 'Questionnaire\ntype',
      width: 160,
      headerColor: creamHeader,
    ),
    SheetColumn(
      key: 'completedBy',
      label: 'Questionnaire to be completed by\n(Parent / carer / Teacher)',
      width: 240,
      headerColor: creamHeader,
    ),
    SheetColumn(
      key: 'genieSmsSentDate',
      label: 'Genie SMS notification sent\n& CNP in Genie (date)',
      width: 210,
      headerColor: creamHeader,
    ),
    SheetColumn(
      key: 'questionnaireDueDate',
      label: 'Questionnaire due date\n(4 weeks after sent date)',
      width: 190,
      headerColor: yellowHeader,
    ),
    SheetColumn(
      key: 'qUploadedToGenieDate',
      label: 'Q uploaded to Genie and\nMarked for Paed review (date)',
      width: 220,
      headerColor: greenHeader,
      isCompletionField: true,
    ),
    SheetColumn(
      key: 'followUpReminderDate',
      label: 'Follow-up email & SMS reminder sent\n& CNP on Genie (date)',
      width: 230,
      headerColor: redHeader,
    ),
    SheetColumn(
      key: 'removeIfNotReceivedDate',
      label: 'Questionnaire to be removed if not received by\n(Date 4 weeks after follow up)',
      width: 240,
      headerColor: yellowHeader,
    ),
    SheetColumn(
      key: 'notifyPaedDate',
      label: 'Notify Paed via Genie Task re:\nQ not returned by due date - deleted & CNP (date)',
      width: 260,
      headerColor: redHeader,
    ),
  ],
);

const SheetConfig clinPsychSwAsdConfig = SheetConfig(
  id: 'clinpsych_sw_asd',
  shortTitle: 'Clin Psych / SW / ASD',
  title: 'MHS & WPS Clin Psych, SW & ASD client questionnaire tracking spreadsheet',
  completedField: 'qUploadedToCdisDate',
  columns: [
    SheetColumn(
      key: 'clientName',
      label: 'Client name\n(Surname, first name)',
      width: 220,
      headerColor: greyHeader,
    ),
    SheetColumn(
      key: 'clientDob',
      label: 'Client DOB',
      width: 130,
      headerColor: greyHeader,
    ),
    SheetColumn(
      key: 'umrn',
      label: 'UMRN',
      width: 120,
      headerColor: greyHeader,
    ),
    SheetColumn(
      key: 'cpAsd',
      label: 'CP/ASD',
      width: 110,
      headerColor: blueHeader,
    ),
    SheetColumn(
      key: 'requestorName',
      label: 'Requestor name',
      width: 180,
      headerColor: blueHeader,
    ),
    SheetColumn(
      key: 'questionnairePlatform',
      label: 'Questionnaire\nplatform',
      width: 150,
      headerColor: creamHeader,
    ),
    SheetColumn(
      key: 'questionnaireType',
      label: 'Questionnaire type',
      width: 190,
      headerColor: creamHeader,
    ),
    SheetColumn(
      key: 'completedBy',
      label: 'Questionnaire to be completed by\n(Parent / carer / Teacher)',
      width: 240,
      headerColor: creamHeader,
    ),
    SheetColumn(
      key: 'optusSmsSentDate',
      label: 'Optus SMS notification sent\n& CNP in CDIS (date)',
      width: 220,
      headerColor: creamHeader,
    ),
    SheetColumn(
      key: 'questionnaireDueDate',
      label: 'Questionnaire due',
      width: 180,
      headerColor: yellowHeader,
    ),
    SheetColumn(
      key: 'qUploadedToCdisDate',
      label: 'Q uploaded to CDIS\n(and Genie if active to Paed)\nand email sent to request',
      width: 260,
      headerColor: greenHeader,
      isCompletionField: true,
    ),
    SheetColumn(
      key: 'followUpReminderDate',
      label: 'Follow-up email & SMS reminder sent\n& CNP on CDIS (date)',
      width: 230,
      headerColor: redHeader,
    ),
    SheetColumn(
      key: 'removeIfNotReceivedDate',
      label: 'Questionnaire to be removed if not received by\n(Date 4 weeks after follow up)',
      width: 250,
      headerColor: yellowHeader,
    ),
    SheetColumn(
      key: 'additionalInfo',
      label: 'Additional info / comments',
      width: 300,
      headerColor: whiteHeader,
    ),
  ],
);

const SheetConfig completedConfig = SheetConfig(
  id: 'completed',
  shortTitle: 'Completed',
  title: 'COMPLETED / DELETED CDS PAED CLIENT QUESTIONNAIRES',
  completedField: null,
  columns: [
    SheetColumn(
      key: 'clientName',
      label: 'Client name\n(Surname, first name)',
      width: 220,
      headerColor: greyHeader,
    ),
    SheetColumn(
      key: 'clientDob',
      label: 'Client DOB',
      width: 130,
      headerColor: greyHeader,
    ),
    SheetColumn(
      key: 'umrn',
      label: 'UMRN',
      width: 120,
      headerColor: greyHeader,
    ),
    SheetColumn(
      key: 'localCdsCatchmentSite',
      label: 'Local catchment CDS site',
      width: 180,
      headerColor: blueHeader,
    ),
    SheetColumn(
      key: 'paediatricianClinic',
      label: 'Paediatrician / Clinic',
      width: 250,
      headerColor: blueHeader,
    ),
    SheetColumn(
      key: 'questionnairePlatform',
      label: 'Questionnaire platform',
      width: 170,
      headerColor: creamHeader,
    ),
    SheetColumn(
      key: 'questionnaireType',
      label: 'Questionnaire name/type',
      width: 210,
      headerColor: creamHeader,
    ),
    SheetColumn(
      key: 'completedBy',
      label: 'Questionnaire to be completed by',
      width: 230,
      headerColor: creamHeader,
    ),
    SheetColumn(
      key: 'questionnaireDueDate',
      label: 'Questionnaire due date',
      width: 180,
      headerColor: yellowHeader,
    ),
    SheetColumn(
      key: 'qUploadedToGenieDate',
      label: 'Date Q uploaded to Genie',
      width: 190,
      headerColor: greenHeader,
    ),
    SheetColumn(
      key: 'qUploadedToCdisDate',
      label: 'Date Q uploaded to CDIS',
      width: 190,
      headerColor: greenHeader,
    ),
    SheetColumn(
      key: 'sourceSheetTitle',
      label: 'Moved from',
      width: 230,
      headerColor: greyHeader,
    ),
  ],
);