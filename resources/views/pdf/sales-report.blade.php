<!doctype html>
<html>
<head><meta charset="utf-8"><title>Sales Report</title></head>
<body>
    <h1>Sales Report</h1>
    <table border="1" cellspacing="0" cellpadding="6">
        <thead><tr><th>Label</th><th>Total</th></tr></thead>
        <tbody>
        @foreach($rows as $row)
            <tr><td>{{ $row['label'] }}</td><td>{{ $row['total'] }}</td></tr>
        @endforeach
        </tbody>
    </table>
</body>
</html>
