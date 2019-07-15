### This gist is for sampling from a 3x2 "Bi-Categorical" distributions and
### running Deep Learning with keras in R to predict Cramer's V
### Author: Giora Simchoni

# Load necessary libraries
library(tidyverse)
library(abind)
library(keras)

# Define Cramer's V function (or get it from various packages)
cramer_v <- function(x) {
  unname(sqrt(chisq.test(x)$statistic /(sum(x) * (min(nrow(x),ncol(x)) - 1))))
}

# Example
p1 <- c(0.2, 0.3, 0.5) # probability of "columns" marginal categorical dist, 3 levels
n <- 1000
tab <- matrix(rmultinom(1, n, prob = c(p1/3, 2*p1/3)), 2, 3, byrow = TRUE)
print(tab) # the 3x2 cross-table
print(cramer_v(tab)) # Cramer's V

# Creating many trios summing up to 1, for the "columns" marginal distribution
my_seq <- seq(0.05,0.95,0.01)
trios <- tibble(a = my_seq, b = my_seq, c = my_seq) %>%
  expand(a, b, c) %>%
  mutate(total = a + b + c) %>%
  filter(total == 1) %>%
  select(-total)
print(trios)

# Replicating trios for a few times, each time for a different "Rows" distribution
# "Rows" distribution has 2 levels only, so we only need one probability to define it
share_1st_group_opts <- seq(0.1, 0.9, 0.1)
trios_expanded <- trios %>%
  mutate(n = length(share_1st_group_opts)) %>%
  uncount(n) %>%
  mutate(share_1st_group = rep(share_1st_group_opts, nrow(trios)))
print(trios_expanded)

# Function to sample a 3x2 "Bi-Categorical" distribution - INDEPENDENT
# Function returns a list of the cross-table, Cramer's V and chi-square significance
sampleBiCategoricalIndependent <- function(a, b, c, share_1st_group, n = 843) {
  p <- c(a, b, c)
  crosstab <- matrix(
    rmultinom(1, n, prob = c(p*share_1st_group, p* (1-share_1st_group))),
    2, 3, byrow = TRUE
  )
  crv <- cramer_v(crosstab)
  sig <- chisq.test(crosstab)$p.value < 0.05
  
  return(list(
    crosstab = crosstab,
    crv = crv,
    sig = sig
  ))
}

# Example
print(sampleBiCategoricalIndependent(0.2, 0.2, 0.6, 0.5))

# Function to sample a 3x2 "Bi-Categorical" distribution - DEPENDENT
sampleBiCategoricalDependent <- function(i, n = 843) {
  m <- as.matrix(trios[sample(nrow(trios), 2, replace = FALSE),])
  share_1st_group <- sample(share_1st_group_opts, 1)
  p <- c(m[1, ] * share_1st_group, m[2, ] * (1 - share_1st_group))
  crosstab <- matrix(
    rmultinom(1, n, prob = p),
    2, 3, byrow = TRUE
  )
  crv <- cramer_v(crosstab)
  sig <- chisq.test(crosstab)$p.value < 0.05
  
  return(list(
    crosstab = crosstab,
    crv = crv,
    sig = sig
  ))
}

# Example
print(sampleBiCategoricalDependent(1))

# Sampling insignificant (independent) distributions/Cramer's V
non_sig_crvs <- trios_expanded %>%
  transmute(res = pmap(list(a, b, c, share_1st_group), sampleBiCategoricalIndependent),
            crv = map_dbl(res, ~.$crv),
            sig = map_lgl(res, ~.$sig))

# Sampling significant (dependent) distributions/Cramer's V
sig_crvs <- tibble(i = 1:20000) %>%
  transmute(res = map(i, sampleBiCategoricalDependent),
            crv = map_dbl(res, ~.$crv),
            sig = map_lgl(res, ~.$sig))

# Binding 10K random of each
data_raw <- rbind(non_sig_crvs, sig_crvs) %>%
  group_by(sig) %>%
  sample_n(10000) %>%
  ungroup()

# Function to create a mosaic plot matrix off a cross-table
# Should return a [1, 60, 60, 1] matrix, for later use by keras
plotMat <- function(res, width = 60) {
  ct <- res$crosstab
  row_sums <- rowSums(ct)
  n <- sum(ct)
  m <- array(0, c(width, width))
  m[rep(round(width * row_sums[1] / n), width), 1:width] <- 1
  m[1:round(width * row_sums[1] / n), rep(round(width * ct[1, 3] / row_sums[1]), round(width * row_sums[1] / n))] <- 1
  m[1:round(width * row_sums[1] / n), rep(round(width * sum(ct[1, 2:3]) / row_sums[1]), round(width * row_sums[1] / n))] <- 1
  m[(round(width * row_sums[1] / n) + 1):width, rep(round(width * ct[2, 3] / row_sums[2]), width - round(width * row_sums[1] / n))] <- 1
  m[(round(width * row_sums[1] / n) + 1):width, rep(round(width * sum(ct[2, 2:3]) / row_sums[2]), width - round(width * row_sums[1] / n))] <- 1
  array(m, c(1, width, width, 1))
}

# Getting one big X matrix, dims should be [20K, 60, 60, 1] (20K samples, each image is 60x60 with 1 color channel)
x <- do.call(abind::abind, list(map(data_raw$res, plotMat), along = 1))
print(dim(x))

# See that a matrix actually represents a mosaic plot:
mosaicplot(data_raw$res[[1]]$crosstab, xlab = "", ylab = "")
image(x[1, , , 1])

# Training sample
trainSamp <- sample(nrow(x), 10000)

# Creating x_train, x_test
x_train <- x[trainSamp, , , , drop = FALSE]
x_test <- x[-trainSamp, , , , drop = FALSE]
rm(x)
invisible(gc())

# First, DL for classification - predicting is plot significant or not (0/1)
y_classification <- rep(0:1, each = 10000)
y_train_cl <- y_classification[trainSamp]
y_test_cl <- y_classification[-trainSamp]

# Necessary params for keras
input_shape <- c(60, 60, 1)
batch_size <- 128
epochs <- 10

# Define model
model_cl <- keras_model_sequential() %>%
  layer_conv_2d(filters = 32, kernel_size = c(3,3), activation = 'relu',
                input_shape = input_shape) %>% 
  layer_conv_2d(filters = 64, kernel_size = c(3,3), activation = 'relu') %>% 
  layer_max_pooling_2d(pool_size = c(2, 2)) %>% 
  layer_dropout(rate = 0.25) %>% 
  layer_flatten() %>% 
  layer_dense(units = 128, activation = 'relu') %>% 
  layer_dropout(rate = 0.5) %>% 
  layer_dense(units = 1, activation = 'sigmoid')

# Compile model
model_cl %>% compile(
  loss = "binary_crossentropy",
  optimizer = optimizer_adadelta(),
  metrics = c('accuracy')
)

# Train model
history <- model_cl %>% fit(
  x_train, y_train_cl,
  batch_size = batch_size,
  epochs = epochs,
  validation_split = 0.2,
  callbacks = list(callback_early_stopping(
    monitor='val_loss', min_delta = 0.01, patience = 2))
)

scores <- model_cl %>% evaluate(
  x_test, y_test_cl, verbose = 0
)

cat('Test loss:', scores[[1]], '\n')
cat('Test accuracy:', scores[[2]], '\n')

# Second, DL for regression - predicting Cramer's V
# Notice changes to params, not only loss function
y_regression <- data_raw$crv
y_train_reg <- y_regression[trainSamp]
y_test_reg <- y_regression[-trainSamp]

# Define model
model_reg <- keras_model_sequential() %>%
  layer_conv_2d(filters = 32, kernel_size = c(3,3), activation = 'relu',
                input_shape = input_shape) %>% 
  layer_conv_2d(filters = 64, kernel_size = c(3,3), activation = 'relu') %>% 
  layer_max_pooling_2d(pool_size = c(2, 2)) %>% 
  layer_dropout(rate = 0.25) %>% 
  layer_flatten() %>% 
  layer_dense(units = 128, activation = 'relu') %>% 
  layer_dropout(rate = 0.5) %>% 
  layer_dense(units = 1)

# Compile model
model_reg %>% compile(
  loss = "mean_squared_error",
  optimizer = optimizer_adadelta(),
  metrics = "mean_squared_error"
)

# Train model
epochs <- 100

history <- model_reg %>% fit(
  x_train, y_train_reg,
  batch_size = batch_size,
  epochs = epochs,
  validation_split = 0.2,
  callbacks = list(callback_early_stopping(
    monitor='val_loss', min_delta = 0.00001, patience = 10))
)

scores <- model_reg %>% evaluate(
  x_test, y_test_reg, verbose = 0
)

cat('Test MSE:', scores[[1]], '\n')

# Plotting Cramer's V Predicted vs. True, after capping at 0-1
y_pred <- c(model_reg %>% predict(x_test))
y_pred <- ifelse(y_pred < 0, 0, y_pred)
y_pred <- ifelse(y_pred > 1, 1, y_pred)

plot(y_test_reg, y_pred)
cor(y_test_reg, y_pred)

# Or, with ggplot
ggplot(tibble(test_pearson_r = y_test_reg, predicted_pearson_r = y_pred),
       aes(test_pearson_r, predicted_pearson_r)) + geom_point() +
  labs(title = "Cramer's V: Predicted vs. True",
       subtitle = expression("Trained on 10K mosaic plots from Bivariate-Categorical 3x2 Distributions, n = 843"),
       x = "True V",
       y = "Predicted V")
