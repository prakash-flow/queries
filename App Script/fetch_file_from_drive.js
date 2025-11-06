function attachFilesFromFolder() {
  const folderId = "1bDDQV6efNgnxDp16w7lovKjdH6ILJA4O"; 
  const sheetName = "Sheet1";
  const accCol = 1;
  const linkCol = 6;

  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(sheetName);
  const data = sheet.getRange(2, accCol, sheet.getLastRow() - 1).getValues();

  const folder = DriveApp.getFolderById(folderId);
  const files = folder.getFiles();
  const fileMap = {};

  // Build a map of all files in folder
  while (files.hasNext()) {
    const file = files.next();
    fileMap[file.getName()] = `https://drive.google.com/file/d/${file.getId()}/view?usp=sharing`;
  }

  // Match and attach links
  data.forEach((row, i) => {
    const accNumber = row[0];
    if (!accNumber) return;

    // Find file name that contains accNumber
    const matched = Object.entries(fileMap).find(([name]) => name.includes(accNumber));
    if (matched) {
      const [, link] = matched;
      sheet.getRange(i + 2, linkCol).setValue(link);
      Logger.log(`✅ Linked ${accNumber}`);
    } else {
      Logger.log(`⚠️ Not found: ${accNumber}`);
    }
  });
}