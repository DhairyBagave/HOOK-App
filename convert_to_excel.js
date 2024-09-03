// const admin = require('firebase-admin');
// const ExcelJS = require('exceljs');
// const fs = require('fs');

// admin.initializeApp({
//   credential: admin.credential.cert(require('C:/Users/Dhairy Bagave/Downloads/DimensionSixApp-main/dimensionsixebike-firebase-adminsdk-axi4v-48a725d312.json'))
// });

// const db = admin.firestore();

// async function getAllCollections() {
//   const collections = await db.listCollections();
//   return collections.map(col => col.id);
// }

// async function fetchCollectionData(collectionName) {
//   const snapshot = await db.collection(collectionName).get();
//   const data = [];

//   snapshot.forEach(doc => {
//     data.push(doc.data());
//   });

//   return data;
// }

// async function exportToExcel() {
//   const workbook = new ExcelJS.Workbook();

//   try {
//     const collections = await getAllCollections();
    
//     for (const collectionName of collections) {
//       const data = await fetchCollectionData(collectionName);
      
//       if (data.length > 0) {
//         const worksheet = workbook.addWorksheet(collectionName);
        
//         // Add column headers
//         const columns = Object.keys(data[0]).map(key => ({ header: key, key: key }));
//         worksheet.columns = columns;
        
//         // Add rows
//         data.forEach(item => {
//           worksheet.addRow(item);
//         });
//       }
//     }
    
//     await workbook.xlsx.writeFile('firestore_data.xlsx');
//     console.log('Data exported successfully!');
//   } catch (error) {
//     console.error('Error exporting data:', error);
//   }
// }

// exportToExcel();





const admin = require('firebase-admin');
const ExcelJS = require('exceljs');
const fs = require('fs');

admin.initializeApp({
  credential: admin.credential.cert(require('C:/Users/Dhairy Bagave/Downloads/DimensionSixApp-main/dimensionsixebike-firebase-adminsdk-axi4v-48a725d312.json'))
});

const db = admin.firestore();

async function getAllCollections() {
  const collections = await db.listCollections();
  return collections.map(col => col.id);
}

async function fetchCollectionData(collectionName) {
  const snapshot = await db.collection(collectionName).get();
  const data = [];

  snapshot.forEach(doc => {
    data.push(doc.data());
  });

  return data;
}

async function exportToExcel() {
  const workbook = new ExcelJS.Workbook();
  const collections = await getAllCollections();

  try {
    for (let i = 0; i < collections.length; i++) {
      const collectionName = collections[i];
      const data = await fetchCollectionData(collectionName);

      if (data.length > 0) {
        // Ensure worksheet name is unique by appending an index
        const worksheetName = `${collectionName}_${i}`;
        const worksheet = workbook.addWorksheet(worksheetName);

        // Add column headers
        const columns = Object.keys(data[0]).map(key => ({ header: key, key: key }));
        worksheet.columns = columns;

        // Add rows
        data.forEach(item => {
          worksheet.addRow(item);
        });
      }
    }

    await workbook.xlsx.writeFile('firestore_data.xlsx');
    console.log('Data exported successfully!');
  } catch (error) {
    console.error('Error exporting data:', error);
  }
}

exportToExcel();


