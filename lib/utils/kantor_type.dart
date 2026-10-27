String jenisKantorLabel(Object? code) {
  switch (code?.toString().trim()) {
    case '1':
      return 'Kantor Pusat';
    case '2':
      return 'Kantor Cabang';
    case '3':
      return 'Kantor Operasional';
    case '4':
      return 'Kantor Divisi';
    case '5':
      return 'Kantor Unit';
    case '6':
      return 'Kantor Penjualan';
    default:
      return 'Jenis kantor tidak diketahui';
  }
}

bool isKantorPusat(Object? code) => code?.toString().trim() == '1';
