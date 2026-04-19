output "raw_bucket_name"      { value = aws_s3_bucket.raw.id }
output "texts_bucket_name"    { value = aws_s3_bucket.texts.id }
output "audio_bucket_name"    { value = aws_s3_bucket.audio.id }
output "frontend_bucket_name" { value = aws_s3_bucket.frontend.id }

output "raw_bucket_arn"      { value = aws_s3_bucket.raw.arn }
output "texts_bucket_arn"    { value = aws_s3_bucket.texts.arn }
output "audio_bucket_arn"    { value = aws_s3_bucket.audio.arn }
output "frontend_bucket_arn" { value = aws_s3_bucket.frontend.arn }

output "books_table_name"  { value = aws_dynamodb_table.books.name }
output "books_table_arn"   { value = aws_dynamodb_table.books.arn }
output "books_stream_arn"  { value = aws_dynamodb_table.books.stream_arn }
