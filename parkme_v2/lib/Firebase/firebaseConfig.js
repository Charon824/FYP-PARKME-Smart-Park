
import { initializeApp } from "firebase/app";
import { getAnalytics } from "firebase/analytics";
// TODO: Add SDKs for Firebase products that you want to use
// https://firebase.google.com/docs/web/setup#available-libraries

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
  apiKey: "AIzaSyCAhnD5OKPltpWl8MwlLJQ-1vmcnxXmgaA",
  authDomain: "parkme-22056469.firebaseapp.com",
  projectId: "parkme-22056469",
  storageBucket: "parkme-22056469.firebasestorage.app",
  messagingSenderId: "264720095382",
  appId: "1:264720095382:web:08ceb91d5c7edfecdbcab7",
  measurementId: "G-V8RD9EX357"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const analytics = getAnalytics(app);