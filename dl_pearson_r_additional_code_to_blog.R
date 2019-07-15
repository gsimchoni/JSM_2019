### Some additional code for the Pearson's r DL model
### Assumes you have ran the regression model `model_reg` as detailed in Book'em Danno! blog post
### http://giorasimchoni.com/2018/02/07/2018-02-07-book-em-danno/
### Which means you also have functions like sampleBVN and plotMat defined

# Sampling a high-correlation Bivariate Normal distribution, small sample
high_cor <- sampleBVN(0.9, n = 10)
ggplot(tibble(X = high_cor$bvn[, 1], Y = high_cor$bvn[, 2]), aes(X, Y)) +
  geom_point()
print(high_cor$r)

# Convert plot to [1, 60, 60, 1] matrix
high_cor_m <- plotMat(high_cor$bvn)

# Predict correlation
model_reg$predict(high_cor_m)

# You can also see that although correlation predicted is low,
# the model is still picking the right plot in a lineup
high_cor_df <- data.frame(high_cor$bvn)
colnames(high_cor_df) <- c("x", "y")
lineup_data_high_cor <- lineup(null_permute("x"), high_cor_df)

ggplot(lineup_data_high_cor, aes(x, y)) +
  geom_point() +
  facet_wrap(~ .sample)

# Model's choice
lineup_data_high_cor %>%
  split(., .$.sample) %>%
  map(plotMat) %>%
  map_dbl(model_reg$predict, verbose = 0) %>%
  which.max()

# Original plot
attr(lineup_data_high_cor, "pos")

###############################################################

# check prediction for a simple image, Cartman (already sized to 60X60 grayscale)
library(magick)
img <- image_read("images/cartman.jpeg")
img_array <- image_data(img) %>% as.integer()
print(dim(img_array))

# See the matrix
image(img_array[,,1])

# Make matrix dims [1, 60, 60, 1] for keras model
img_array <- array(img_array, dim = c(1, 60, 60, 1))
print(dim(img_array))

# Predict correlation...
model_reg$predict(img_array)